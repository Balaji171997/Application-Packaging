##############################################################
# Build.ps1
# The predecessor reuse pipeline. Implements Plan sections 1 & 2:
#   - one-dot-prefix version swap on authored code (via Core.ps1)
#   - uninstall-previous block processed in its OWN lane:
#       excise existing -> build pinned -> inject LAST, after the swap.
# Versions live in exactly two pinned places:
#   AppVersion = NEW   |   uninstall-previous block = PREDECESSOR.
##############################################################

# --- Find an existing "If ((Get-(ADT|Installed)Application...)) { ... }" block.
#     QUOTE- AND PAREN-AWARE: the condition contains an MSI ProductCode like
#     '{GUID}', so a naive "first '{'" brace walk latches onto the GUID brace
#     and mangles the block (this was a real recurring bug). We first close the
#     If(...) condition by paren-matching, THEN brace-walk the body - both while
#     skipping anything inside '...' or "..." strings.
# Normalise an identifier for FUZZY comparison: strip everything but letters/digits, lowercase. So "PRODIS.Authoring",
# "PRODISAuthoring" and "PRODIS Authoring" all collapse to "prodisauthoring".
function Get-PBNormToken { param([string]$s) return (("$s" -replace '[^A-Za-z0-9]', '').ToLower()) }

function Find-ExistingUninstallBlock {
    param([string]$Code, [hashtable]$Identity)
    if (-not $Code) { return @{ Found = $false } }
    $ourApp   = if ($Identity) { Get-PBNormToken "$($Identity.AppName)" } else { '' }
    $ourBrand = if ($Identity) { Get-PBNormToken "$($Identity.Vendor)$($Identity.AppName)" } else { '' }
    # Evaluate EACH "If ( ... Get-(ADT|Installed)Application ... )" candidate; a block is a genuine PREDECESSOR-UNINSTALL
    # block (safe to excise) ONLY when it passes ALL of these. Any failure => KEEP it in the body (it belongs to a
    # dependency gate or a different component, not to removing our predecessor). Rules (user-specified):
    #  (1) POSITIVE condition - not "if(!(...))"/"if(-not(...))" (a negated check is a DEPENDENCY GATE, e.g. the
    #      "if(!(Get-InstalledApplication '*CodeMeter Runtime Kit*')){Exit-Script}else{...}" gate).
    #  (2) NO else/elseif branch - a real uninstall block is a plain "If (installed) { remove }"; an if/else is
    #      conditional logic to preserve (applies in ALL cases, even with a matching branding key).
    #  (3) It refers to OUR predecessor: its Get-*Application -Name fuzzy-matches our app name, OR the block carries our
    #      VWG\CM branding key. A block that NAMES a DIFFERENT app (VC++, .NET runtimes, ...) with neither is KEPT. A
    #      ProductCode-only block (no -Name) stays excisable; a matching branding key forces removal regardless of name.
    foreach ($cand in [regex]::Matches($Code, '(?i)\bIf\s*\(.*?Get-(ADT|Installed)Application\b')) {
        if ($cand.Value -match '(?i)\bIf\s*\(\s*(?:!|-not\b)') { continue }   # (1) negated -> dependency gate -> keep
        # paren-match the condition to find the body's opening brace
        $ifMatch = [regex]::Match($Code.Substring($cand.Index), '(?i)\bIf\s*\(')
        $i = $cand.Index + $ifMatch.Length - 1
        $depth = 0; $q = $null
        while ($i -lt $Code.Length) {
            $c = $Code[$i]
            if ($q) { if ($c -eq $q) { $q = $null } }
            elseif ($c -eq "'" -or $c -eq '"') { $q = $c }
            elseif ($c -eq '(') { $depth++ }
            elseif ($c -eq ')') { $depth--; if ($depth -eq 0) { break } }
            $i++
        }
        $open = $Code.IndexOf('{', $i)
        if ($open -lt 0) { continue }
        $depth = 0; $q = $null; $end = -1
        for ($j = $open; $j -lt $Code.Length; $j++) {
            $c = $Code[$j]
            if ($q) { if ($c -eq $q) { $q = $null } }
            elseif ($c -eq "'" -or $c -eq '"') { $q = $c }
            elseif ($c -eq '{') { $depth++ }
            elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $j; break } }
        }
        if ($end -lt 0) { continue }
        # (2) else/elseif right after the body -> conditional logic -> keep.
        $after = if (($end + 1) -lt $Code.Length) { $Code.Substring($end + 1) } else { '' }
        if ($after -match '^\s*(?:else|elseif)\b') { continue }
        # (3) different-component guard: KEEP only when the block NAMES a DIFFERENT app (a -Name that fuzzy-matches
        #     neither our app name nor our VWG\CM branding key). ProductCode-only blocks stay excisable.
        if ($Identity) {
            $blockText = $Code.Substring($cand.Index, $end - $cand.Index + 1)
            $nameM  = [regex]::Match($blockText, "(?i)Get-(?:ADT|Installed)Application\b[^\r\n]*?-Name\s+(?:'([^']*)'|""([^""]*)"")")
            $blkApp = if ($nameM.Success) { Get-PBNormToken ($nameM.Groups[1].Value + $nameM.Groups[2].Value) } else { '' }
            $brandM = [regex]::Match($blockText, "(?i)VWG\\CM\\([^""'\r\n\)]+)")
            $blkBrand = if ($brandM.Success) { Get-PBNormToken $brandM.Groups[1].Value } else { '' }
            $brandMatches = ($ourBrand -and $blkBrand -and $blkBrand.Contains($ourBrand))
            $appMatches   = ($ourApp -and $blkApp -and ($blkApp.Contains($ourApp) -or $ourApp.Contains($blkApp)))
            if ($nameM.Success -and -not $brandMatches -and -not $appMatches) { continue }   # names a DIFFERENT app -> keep
        }
        # ACCEPTED: a genuine predecessor-uninstall block. WrapperLine = "If ((...)) {" up to and INCLUDING the body's
        # opening brace ($open, found by paren-matching the condition - never a '{GUID}' ProductCode brace).
        return @{ Found = $true; Start = $cand.Index; End = $end; Open = $open
                 Block       = $Code.Substring($cand.Index, $end  - $cand.Index + 1)
                 WrapperLine = $Code.Substring($cand.Index, $open - $cand.Index + 1) }
    }
    return @{ Found = $false }
}

# Excise EVERY existing uninstall block from a Pre-Install body. A predecessor can carry
# more than one (its own upgrade chain); we keep them ALL verbatim, each together with a
# contiguous run of comment lines directly above it (e.g. "#Upgrade <name>"). Returns the
# block strings in document order plus the body with them removed.
function Split-ExistingUninstallBlocks {
    param([string]$Code, [hashtable]$Identity)
    $blocks = New-Object System.Collections.Generic.List[string]
    if (-not $Code) { return @{ Blocks = $blocks; Body = $Code } }
    while ($true) {
        $ex = Find-ExistingUninstallBlock -Code $Code -Identity $Identity
        if (-not $ex.Found) { break }
        $start = $ex.Start
        # absorb a run of comment lines immediately above the If(...) so the "#Upgrade"
        # label stays with its block instead of being orphaned in the body.
        $head = [regex]::Match($Code.Substring(0, $start), '(?:[ \t]*#[^\r\n]*\r?\n)+[ \t]*$')
        if ($head.Success -and ($head.Index + $head.Length) -eq $start) { $start = $head.Index }
        $len = ($ex.End + 1) - $start
        $blocks.Add($Code.Substring($start, $len).Trim())
        $Code = $Code.Remove($start, $len)
    }
    return @{ Blocks = $blocks; Body = $Code.Trim() }
}

# --- Build the uninstall-previous block, pinned to the PREDECESSOR.
#     Body = predecessor Pre + Main + Post uninstall (its MainUninstall already
#     removes the predecessor itself). Detection: MSI -> ProductCode, EXE -> name+version.
# Predecessor's own ProductCode lives in its MAIN-UNINSTALL section.
function Get-PredecessorUninstallPC {
    param([hashtable]$Model)
    $m = [regex]::Match("$($Model.Code.MainUninstallCode)", '\{[0-9A-Fa-f\-]{36}\}')
    if ($m.Success) { return $m.Value }
    return $null
}
# F9: the predecessor's real ARP DisplayName for a name-based Get-ADTApplication detection. The parsed package AppName
# ("Animator4") does NOT match the installed app's DisplayName ("Animator4_v2.8.1_64"), so detection fails. The
# predecessor's own SoftIdent carries it: "HKLM:\...\Uninstall\<subkey> [DisplayVersion=x]". <subkey> is the ARP key -
# for Inno it is "<DisplayName>_is1"; the DisplayName drops the _is1. An MSI subkey is a {GUID} (use -ProductCode, not a
# name) -> return '' so the caller keeps its ProductCode path / falls back to the parsed AppName (+ review item).
function Get-PredecessorDisplayName {
    param([hashtable]$Model)
    $si = if ($Model.Session -and $Model.Session.ContainsKey('SoftIdent')) { "$($Model.Session['SoftIdent'])".Trim("'", '"', ' ') } else { '' }
    if (-not $si) { return '' }
    $m = [regex]::Match($si, '(?i)\\Uninstall\\([^\\\[\r\n"'']+?)\s*(?:\[|$)')
    if (-not $m.Success) { return '' }
    $key = $m.Groups[1].Value.Trim()
    if ($key -match '^\{[0-9A-Fa-f-]{36}\}$') { return '' }   # MSI ProductCode subkey - not a display name
    return ($key -replace '(?i)_is1$', '')                    # Inno "<DisplayName>_is1" -> DisplayName
}

# Body shared by both cases: predecessor Pre + Main + Post uninstall (already
# stripped of template structure by Read-PredecessorModel). Multiple product
# codes inside are kept verbatim - we never parse them.
function Get-UninstallBody {
    param([hashtable]$Model)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($k in 'PreUninstallCode','MainUninstallCode','PostUninstallCode') {
        $seg = "$($Model.Code.$k)".Trim()
        if ($seg) { $parts.Add($seg) }
    }
    $body = ($parts -join "`r`n`r`n")
    # In an uninstall-previous block the reboot-handling scaffold is noise: drop the
    # "##Handling for required reboot" comment and the (commented) Set-MTBReboot line.
    $body = [regex]::Replace($body, '(?im)^[ \t]*#+\s*Handling for required reboot.*\r?\n?', '')
    $body = [regex]::Replace($body, '(?im)^[ \t]*#+\s*Set-MTBReboot\b.*\r?\n?', '')
    # The $flag mechanism belongs to the CURRENT package's Uninstall function (its post-uninstall branding
    # removal is guarded by If($flag)); it is NOT meaningful inside an uninstall-previous block. After the
    # branding-removal boilerplate is stripped the guard is left EMPTY ("If ($flag) { }") - dead code the team
    # flagged. Drop the empty guard, then drop the now-orphan "$flag = $true" if nothing else tests $flag.
    $body = [regex]::Replace($body, '(?im)^[ \t]*If\s*\(\s*\$flag\s*\)\s*\{\s*\}[ \t]*\r?\n?', '')
    if ($body -match '(?i)\$flag' -and $body -notmatch '(?im)If\s*\(\s*\$flag\s*\)') {
        $body = [regex]::Replace($body, '(?im)^[ \t]*\$flag\s*=\s*\$true[ \t]*\r?\n?', '')
    }
    return $body.Trim()
}

# Build the uninstall-previous block.
#   $WrapperLine : Case 1 -> the predecessor's existing (fixed-up) If(...) line.
#                  Case 2 -> $null, we generate it (with branding key).
function New-UninstallPreviousBlock {
    param([hashtable]$Model, [string]$WrapperLine)
    $id   = $Model.Identity
    $ver  = "$($id.Version)"
    $pc   = Get-PredecessorUninstallPC -Model $Model
    $body = Get-UninstallBody -Model $Model
    # A BARE "Remove-MTBDetectionKey" defaults to $AppFullName, which here is the NEW
    # package - wrong, this block removes the PREDECESSOR. Pin bare calls to the
    # predecessor's full name so we delete the predecessor's branding key, not ours.
    # (Calls that already name a key are left alone.)
    if ($id.FullName) {
        $body = [regex]::Replace($body, '(?im)^([ \t]*)Remove-MTBDetectionKey[ \t]*(?=\r?\n|$)',
                                  "`${1}Remove-MTBDetectionKey `"$($id.FullName)`"")
    }
    # GPF: their custom Remove-Branding removes the OLD package's branding key. The predecessor's own copy was stripped
    # as boilerplate (Get-UninstallBody), so a generated block would otherwise leave the predecessor's branding behind.
    # Add Remove-Branding pinned to the predecessor's FullName (mirrors their hand-authored uninstall blocks), inserted
    # before any trailing Set-Reboot so branding removal stays with the rest of the uninstall and reboot stays last.
    $isGpf = (Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF'
    if ($isGpf -and $id.FullName -and ($body -notmatch '(?im)^[ \t]*Remove-Branding\b')) {
        $rb = '##Remove all known old brandings' + "`r`n" +
              'Remove-Branding -InstanceName "' + $id.FullName + '" -AdditionalRegPaths "HKLM:\Software\$($VWG_CurrentRegWow)VWG\InstalledProducts", "HKLM:\Software\$($VWG_CurrentRegWow)VWG\CM"'
        $mReb = [regex]::Match($body, '(?im)^[ \t]*Set-Reboot\b')
        if ($mReb.Success) { $body = $body.Substring(0, $mReb.Index) + $rb + "`r`n`r`n" + $body.Substring($mReb.Index) }
        else { $body = $body.TrimEnd() + "`r`n`r`n" + $rb }
    }
    $indent = [string]::Join("`r`n", (($body -split "`r?`n") | ForEach-Object { '    ' + $_ }))

    if (-not $WrapperLine) {
        # Case 2: generate detection line with branding key.
        $brandKey = "HKLM:\SOFTWARE\VWG\CM\$($id.FullName)"
        # EXE detection by NAME: use the predecessor's real ARP DisplayName from its SoftIdent (F9); fall back to the
        # parsed AppName only if the SoftIdent has no usable name (that fallback is flagged in the review items).
        $pcPart = if ($pc) {
            "Get-ADTApplication -ProductCode `"$pc`""
        } else {
            $dn = Get-PredecessorDisplayName -Model $Model
            if (-not $dn) { $dn = "$($id.AppName)" }
            "Get-ADTApplication -Name `"$dn`""
        }
        $WrapperLine = "If (($pcPart) -and (Test-Path -Path `"$brandKey`")) {"
    }
    # ensure the wrapper line ends with an opening brace
    if ($WrapperLine -notmatch '\{\s*$') { $WrapperLine = $WrapperLine.TrimEnd() + ' {' }

    # Comment header mirrors the team's hand-written packages (e.g. Synera's
    # "#Upgrade <fullname>") rather than a custom delimiter, so generated output
    # looks identical to authored packages and round-trips cleanly.
    $tag = if ($id.FullName) { $id.FullName } else { "$($id.AppName) $ver" }
    @"
#Upgrade $tag
$WrapperLine
    Write-ADTLogEntry -Message 'Removing predecessor version $ver before install.' -Severity 2 -Source `$adtSession.DeployAppScriptFriendlyName
$indent
}
"@
}

# --- Replace the authored region between two markers in the template.
function Set-SectionBody {
    param([string]$Template, [string]$Begin, [string]$End, [string]$Body, [bool]$Pre, [bool]$DropTemplateLogs = $false)
    $m = [regex]::Match($Template, "(?s)($Begin)(.*?)($End)")
    if (-not $m.Success) { return $Template }
    $head = $m.Groups[1].Value
    $mid  = $m.Groups[2].Value
    $tail = $m.Groups[3].Value
    $bodyTrim = "$Body".Trim("`r","`n")
    if (-not $bodyTrim) { return $Template }   # nothing authored: leave the template section PRISTINE

    # PRE-INSTALL split marker: Strip-Boilerplate leaves '#__PB_DIALOGS_SPLIT__' where the predecessor's user-dialogs /
    # process-close block sat. Custom code BEFORE it ran above the dialogs; code AFTER it ran below. Split so each lands
    # on the correct side of the NEW template's dialogs block. Everywhere else uses a sentinel-free recombined body.
    $splitTok  = '#__PB_DIALOGS_SPLIT__'
    $bodyAbove = $bodyTrim; $bodyBelow = ''
    $sx = $bodyTrim.IndexOf($splitTok)
    if ($sx -ge 0) {
        $bodyAbove = $bodyTrim.Substring(0, $sx).Trim("`r","`n"," ","`t")
        $bodyBelow = $bodyTrim.Substring($sx + $splitTok.Length).Trim("`r","`n"," ","`t")
        $bodyTrim  = (@($bodyAbove, $bodyBelow) | Where-Object { $_ }) -join "`r`n`r`n"   # sentinel-free (non-split branches)
        if (-not $bodyTrim) { return $Template }
    }

    # NEVER wipe template lines. Insert the authored body INTO the marker, keeping the
    # template's own scaffolding (e.g. its Write-ADTLogEntry "Start.."/"..successful" lines):
    #   - if the section has a trailing "...successful" log, put body just before it
    #     (i.e. between the template's Start/successful logs);
    #   - else right after the "## <Perform ... tasks here>" marker;
    #   - else at the end of the section.
    # DOUBLE-SUCCESS GUARD: when the carried body has its OWN action-success log (kept because it sits
    # inside an if/else - "ran -> successful / else -> not found"), the template's UNCONDITIONAL trailing
    # success line would log success a second time (and even when the else branch ran). The body owns the
    # outcome messaging then - drop the template's success line. The template's Start line always stays.
    $bodyOwnsSuccess = $bodyTrim -match '(?i)Write-(ADT)?Log(Entry)?\b.*?["''](Installation|Uninstallation|Repair)\s+of\b.{0,160}?\bis\s+successful'
    $bodyOwnsAction  = $bodyOwnsSuccess -or ($bodyTrim -match '(?i)Write-(ADT)?Log(Entry)?\b.*?["'']Start\s+(Installation|Uninstallation|Repair)\b')
    # When the injected body carries its OWN action logging, the template's GENERIC scaffold log lines that just
    # echo "$appVendor $appName $appVersion" are DUPLICATES (the hand-authored predecessor has only the real ones).
    # Drop them so the section reads exactly like the predecessor (team finding: extra Start/Installation-of log
    # lines appeared ABOVE the authored ones in Main-Install/Uninstall/Repair).
    # $DropTemplateLogs = PREDECESSOR REUSE for a Main section: the team decision is "use whatever the predecessor has and
    # remove OUR v4 template log lines" - so drop the template's Start/Installation-of scaffold logs unconditionally (the
    # predecessor carries its own, converted). Whatever regexes catch or not, the predecessor's own logs stay (they don't
    # echo $appVendor $appName $appVersion), only the template scaffold is removed. Empty bodies never reach here (returned
    # PRISTINE above), so a section the predecessor left blank keeps the template scaffold.
    if ($bodyOwnsAction -or $DropTemplateLogs) {
        $mid = [regex]::Replace($mid, '(?im)^[ \t]*Write-ADTLogEntry\b[^\r\n]*\$appVendor[ \t]+\$appName[ \t]+\$appVersion[^\r\n]*\r?\n?', '')
    }
    if ($DropTemplateLogs) {
        # PREDECESSOR REUSE, Main section: the team decision is "use whatever the predecessor has" - the scaffold
        # logs are now gone (above), so keep only the template's remaining scaffolding (the UseDialogs block) and
        # append the predecessor body after it. Removing the log LINES left the whitespace-only lines that sat
        # around them (the template indents the region), so first blank those out and collapse any run of blank
        # lines, then drop trailing blanks and add exactly one clean blank line before the body. Dedicated path -
        # the fresh/owns-action success/marker logic below is skipped entirely for reuse.
        $mid = [regex]::Replace($mid, '(?m)^[ \t]+\r?$', '')
        $mid = [regex]::Replace($mid, '(\r?\n)(\r?\n)+', "`r`n`r`n")
        $newMid = $mid.TrimEnd("`r","`n") + "`r`n`r`n" + $bodyTrim + "`r`n"
        return $Template.Remove($m.Index, $m.Length).Insert($m.Index, $head + $newMid + $tail)
    }
    $succ = [regex]::Match($mid, '(?m)^[ \t]*Write-ADTLogEntry\b.*?successful.*$')
    if ($succ.Success -and $bodyOwnsSuccess) {
        $before = $mid.Substring(0, $succ.Index).TrimEnd("`r","`n")
        $after  = $mid.Substring($succ.Index + $succ.Length)   # text after the removed template success line
        $newMid = $before + "`r`n`r`n" + $bodyTrim + $after
    } elseif ($succ.Success) {
        $before = $mid.Substring(0, $succ.Index).TrimEnd("`r","`n")
        $after  = $mid.Substring($succ.Index)
        $newMid = $before + "`r`n`r`n" + $bodyTrim + "`r`n`r`n" + $after
    } else {
        $mk = [regex]::Match($mid, '(?s)^.*?##\s*<Perform.*?tasks here>[^\r\n]*\r?\n')
        # POST-* sections: the template owns a trailing "## Branding Install/Uninstall" + "## Handling for
        # required reboot" block that MUST stay LAST (team finding: branding/reboot were emitted FIRST because
        # the body was appended after them). Insert the authored body BEFORE that block so it trails.
        $brand = [regex]::Match($mid, '(?m)^[ \t]*##[ \t]*(Branding[ \t]+(?:Install|Uninstall)|Handling for required reboot)\b')
        # PRE sections + HTML prompt: the carried code must sit ABOVE the proc-close / "user dialogs (deprecated)" block,
        # not after it. Two findings:
        #   - "HTML prompt (Show-HTMLInstallationWelcome) should be above the UseDialogs block as per predecessor".
        #   - Predecessor PRE-INSTALL custom code (e.g. a "Checking Dependency Dot Net Framework" block) that ran BEFORE
        #     closing the processes must STAY before it - the tool was relocating it AFTER the dialogs block. Since the GPF
        #     template's PRE-* sections end with the UseDialogs block (nothing follows it), ANY PRE body (Pre=$true) is
        #     inserted just before that block - i.e. between the reboot check and the dialogs, exactly as in the predecessor.
        # Anchor = the template's "# user dialogs (deprecated)" line. MAIN sections never reach here (they take the
        # success-log path above); POST sections have Pre=$false and fall to the branding anchor below.
        $htmlAnchor = [regex]::Match($mid, '(?im)^[ \t]*#[ \t]*user dialogs \(deprecated\)')
        if ($mk.Success) {
            $newMid = $mk.Value + $bodyTrim + "`r`n" + $mid.Substring($mk.Length)
        } elseif ($htmlAnchor.Success -and ($Pre -or ($bodyTrim -match '(?i)Show-HTMLInstallationWelcome'))) {
            $before = $mid.Substring(0, $htmlAnchor.Index).TrimEnd("`r","`n")
            $after  = $mid.Substring($htmlAnchor.Index).Trim("`r","`n")
            # #2: re-indent each carried block to the user-dialogs line's indent so it lines up with the surrounding
            # template code (the predecessor body is usually at column 0). Only when a block isn't already indented that far.
            $anchorIndent = [regex]::Match($htmlAnchor.Value, '^[ \t]*').Value
            $reindent = {
                param([string]$blk)
                if (-not $blk) { return '' }
                if (-not $anchorIndent) { return $blk }
                return (Set-CarriedBlockIndent -Body $blk -Prefix $anchorIndent)
            }
            # ABOVE-dialogs custom code -> between the reboot check ($before) and the dialogs block ($after).
            # BELOW-dialogs custom code -> AFTER the dialogs block (the GPF PRE section ends with that block).
            $parts = New-Object System.Collections.Generic.List[string]
            $bt = "$before".Trim("`r","`n"); if ($bt) { $parts.Add($bt) }
            $ab = & $reindent $bodyAbove;    if ($ab) { $parts.Add($ab) }
            if ($after) { $parts.Add($after) }
            $bl = & $reindent $bodyBelow;    if ($bl) { $parts.Add($bl) }
            $newMid = ($parts -join "`r`n`r`n") + "`r`n"
        } elseif ($brand.Success) {
            $before = $mid.Substring(0, $brand.Index).TrimEnd("`r","`n")
            $after  = $mid.Substring($brand.Index)
            $newMid = $before + "`r`n`r`n" + $bodyTrim + "`r`n`r`n" + $after
        } else {
            $newMid = $mid.TrimEnd("`r","`n") + "`r`n" + $bodyTrim + "`r`n"
        }
    }
    return $Template.Remove($m.Index, $m.Length).Insert($m.Index, $head + $newMid + $tail)
}

# --- Narrow installer swap on a command body: old filename->new, old PC->new.
function Swap-InstallerRefs {
    param([string]$Body, [hashtable]$Map)
    if (-not $Body) { return $Body }
    foreach ($pair in $Map.GetEnumerator()) {
        if ($pair.Key -and $pair.Value -and $pair.Key -ne $pair.Value) {
            $Body = $Body.Replace($pair.Key, $pair.Value)
        }
    }
    return $Body
}


# Collapse the team's verbose branding-removal call to the short positional form:
#   Remove-MTBDetectionKey -InstanceName "X" -AdditionalRegPaths "...","..."  ->  Remove-MTBDetectionKey "X"
# The module applies its default reg paths; the reused package only needs the instance name.
function Simplify-RemoveDetectionKey {
    param([string]$Text)
    if (-not $Text) { return $Text }
    return [regex]::Replace($Text,
        '(?im)^([ \t]*)Remove-MTBDetectionKey[ \t]+-InstanceName[ \t]+("[^"]*"|''[^'']*'')[^\r\n]*',
        '${1}Remove-MTBDetectionKey ${2}')
}

# Drop the predecessor's branding-removal from a POST-UNINSTALLATION section body: the fresh
# template OWNS "## Removing Branding Detection Key / Remove-MTBDetectionKey" there, and the
# predecessor-uninstall block (Get-UninstallBody) carries its own copy at its end. Removes the
# "## Branding Uninstall" / "## Removing Branding Detection Key" comment lines and any BARE
# Remove-MTBDetectionKey (no arguments); a targeted "Remove-MTBDetectionKey "X"" is left alone.
function Remove-SectionBrandingUninstall {
    param([string]$Body)
    if (-not $Body) { return $Body }
    $Body = [regex]::Replace($Body, '(?im)^[ \t]*#+[ \t]*(Branding Uninstall|Removing Branding Detection Key)\b.*\r?\n?', '')
    $Body = [regex]::Replace($Body, '(?im)^[ \t]*Remove-MTBDetectionKey[ \t]*\r?\n?', '')
    return $Body
}

# PRE-REPAIR runs as "uninstall before reinstall" - it must NOT remove the branding key or
# trigger a reboot (those belong to a real uninstall). Drop Remove-MTBDetectionKey and
# Set-MTBReboot (commented or live) plus their comment headers from a Pre-Repair body.
function Remove-PreRepairNoise {
    param([string]$Body)
    if (-not $Body) { return $Body }
    $Body = [regex]::Replace($Body, '(?im)^[ \t]*#+[ \t]*(Branding Uninstall|Removing Branding Detection Key|Handling for required reboot)\b.*\r?\n?', '')
    $Body = [regex]::Replace($Body, '(?im)^[ \t]*#*[ \t]*Remove-MTBDetectionKey\b[^\r\n]*\r?\n?', '')
    $Body = [regex]::Replace($Body, '(?im)^[ \t]*#*[ \t]*Set-MTBReboot\b[^\r\n]*\r?\n?', '')
    return $Body
}

# Remove the predecessor's SELF-uninstall guard from the pre-install body: a bare (no If-wrapper) block headed
#   ##Uninstalling "<Vendor> <App> <version>" if present
#   Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '{...}'   (+ ##Removing Folder / #Removing TAG / IfEmpty cleanup)
# It uninstalls the predecessor's OWN version before install. On reuse the version is swapped to the CURRENT one, so it
# reads as "uninstall the current version in pre-install" AND duplicates the generated immediate-predecessor block that
# already removes the same ProductCode. Team decision: drop it (only the generated immediate-predecessor block remains).
function Remove-SelfUninstallGuard {
    param([string]$Body)
    if (-not $Body -or $Body -notmatch '(?im)^[ \t]*##\s*Uninstalling\s+"[^"]*"\s+if\s+present\b') { return $Body }
    $lines = $Body -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $lines.Count) {
        if ($lines[$i] -match '^[ \t]*##\s*Uninstalling\s+"[^"]*"\s+if\s+present\b') {
            $i++            # skip the header
            # CONSERVATIVE: consume ONLY the guard's OWN known statements. The FIRST line that is not part of the guard
            # (a custom comment, a different statement, the next section) STOPS the removal - so no legitimate pre-install
            # code before/after the guard is ever lost. Order of parts is flexible; each is optional except the uninstall.
            while ($i -lt $lines.Count) {
                $t = $lines[$i].Trim()
                if ($t -eq '') { $i++; continue }                                                     # blank inside the guard
                if ($t -match "^Start-ADT(MsiProcess|Process)\b.*(?i)uninstall") { $i++; continue }    # the uninstall call itself
                if ($t -match '^##\s*Removing Folder if present\b') { $i++; if ($i -lt $lines.Count -and $lines[$i].Trim() -match '^Remove-ADTFolder\b') { $i++ }; continue }
                if ($t -match '^#\s*Removing TAG registry\b')       { $i++; if ($i -lt $lines.Count -and $lines[$i].Trim() -match '^Remove-ADTRegistryKey\b') { $i++ }; continue }
                if ($t -match '^#\s*Removing registry( key)? IfEmpty\b') {
                    $i++                                                                               # consume the following If(Test-Path){...} by brace depth
                    $depth = 0; $started = $false
                    while ($i -lt $lines.Count) {
                        $depth += ([regex]::Matches($lines[$i],'\{')).Count - ([regex]::Matches($lines[$i],'\}')).Count
                        if ($depth -gt 0) { $started = $true }
                        $i++
                        if ($started -and $depth -le 0) { break }
                    }
                    continue
                }
                break                                                                                 # NOT a guard part -> stop; everything else stays intact
            }
            while ($i -lt $lines.Count -and $lines[$i].Trim() -eq '') { $i++ }                         # trailing blank(s)
            continue
        }
        $out.Add($lines[$i]); $i++
    }
    return ($out -join "`r`n")
}

function Insert-IntoPreInstall {
    param([string]$Script, [hashtable]$Section, [string]$Block)
    $Block = [regex]::Replace("$Block", '(?m)^[ \t]*#__PB_DIALOGS_SPLIT__[ \t]*\r?\n?', '')   # never carry the internal split marker
    # MTB template: insert right after the "## <Perform ... tasks here>" author marker (top of the section).
    $m = [regex]::Match($Script, "(?s)($($Section.B))(.*?)##\s*<Perform.*?tasks here>\s*\r?\n")
    if ($m.Success) { return $Script.Insert($m.Index + $m.Length, "`r`n" + $Block + "`r`n") }
    # GPF template (no author marker): place the uninstall-previous group AFTER the whole user-dialogs / process-close
    # block - below the dialogs, matching where the team's predecessors put it - NEVER between the reboot check and the
    # dialogs (which would nest it inside any carried custom code that sits there). Locate the section, then brace-match
    # the "if (...UseDialogs...){ ... }" block and insert right after its closing brace.
    $sec = [regex]::Match($Script, "(?s)($($Section.B))(.*?)($($Section.E))")
    if ($sec.Success) {
        $mid = $sec.Groups[2].Value
        $dlg = [regex]::Match($mid, '(?im)^[ \t]*#[ \t]*user dialogs \(deprecated\)[^\r\n]*\r?\n')
        if ($dlg.Success) {
            # find the "if (...) {" that opens the dialogs block, then walk braces (ignoring quotes) to its close.
            $ifm = [regex]::Match($mid.Substring($dlg.Index + $dlg.Length), '(?im)^[ \t]*if\s*\(')
            if ($ifm.Success) {
                $j = $dlg.Index + $dlg.Length + $ifm.Index
                $open = $mid.IndexOf('{', $j)
                if ($open -ge 0) {
                    $depth = 0; $q = $null; $k = $open; $endPos = -1
                    while ($k -lt $mid.Length) {
                        $c = $mid[$k]
                        if ($q) { if ($c -eq $q) { $q = $null } }
                        elseif ($c -eq "'" -or $c -eq '"') { $q = $c }
                        elseif ($c -eq '{') { $depth++ }
                        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $endPos = $k; break } }
                        $k++
                    }
                    if ($endPos -ge 0) {
                        $insAt = $sec.Index + $sec.Groups[1].Length + $endPos + 1   # absolute index just past the dialogs block's closing brace
                        return $Script.Insert($insAt, "`r`n`r`n" + $Block + "`r`n")
                    }
                }
            }
        }
    }
    # last resort: the sentinel-prefixed body makes Set-SectionBody place it BELOW the dialogs (not between).
    return (Set-SectionBody -Template $Script -Begin $Section.B -End $Section.E -Body ("#__PB_DIALOGS_SPLIT__`r`n" + $Block) -Pre $true)
}

# --- Locate the blank v4 template script. Prefer an extracted PSADT_Template\ folder
#     (dev); else extract PSADT_Template.zip (distribution). Returns the template text
#     of Content\Invoke-AppDeployToolkit.ps1 (NOT the Frontend copy), or $null.
function Get-TemplateScript {
    param([string]$Root)
    if (-not $Root) { $Root = $PSScriptRoot }
    # Brand template folder first (e.g. PSADT_Template_GPF); default MTB = PSADT_Template.
    $tplName = if (Get-Command Get-PBBrand -ErrorAction SilentlyContinue) { Get-PBBrand -Path 'TemplateRoot' -Default 'PSADT_Template' } else { 'PSADT_Template' }
    foreach ($c in @(
        (Join-Path $Root "$tplName\Content\Invoke-AppDeployToolkit.ps1"),
        (Join-Path $Root "Lib\$tplName\Content\Invoke-AppDeployToolkit.ps1"),   # consolidated layout (everything under Lib\)
        (Join-Path $Root 'PSADT_Template\Content\Invoke-AppDeployToolkit.ps1'),
        (Join-Path $Root 'Lib\PSADT_Template\Content\Invoke-AppDeployToolkit.ps1'),
        (Join-Path $Root 'Template\Content\Invoke-AppDeployToolkit.ps1'))) {
        if (Test-Path $c) { return (Read-FileSmart -Path $c) }
    }
    $zip = Join-Path $Root 'PSADT_Template.zip'
    if (-not (Test-Path $zip)) { $zip = Join-Path $Root 'Lib\PSADT_Template.zip' }
    if (Test-Path $zip) {
        try {
            $tmp = Join-Path (Get-WorkPath 'Temp') "PBtpl_$(Get-Random)"
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            $ps1 = Get-ChildItem $tmp -Recurse -Filter 'Invoke-AppDeployToolkit.ps1' -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notmatch '\\Frontend\\' } | Select-Object -First 1
            if ($ps1) { return (Read-FileSmart -Path $ps1.FullName) }
        } catch { Write-Log "Template zip extract failed: $($_.Exception.Message)" Warning }
    }
    Write-Log "Blank template not found under $Root (PSADT_Template\ or PSADT_Template.zip)." Warning
    return $null
}

# --- $adtSession block helpers. The blank template's $adtSession is empty; we take the
#     predecessor's whole block (all MTB config) then retarget identity for the new pkg.
function Get-AdtSessionBlock {
    param([string]$Text)
    if (-not $Text) { return $null }
    $m = [regex]::Match($Text, '(?s)\$adtSession\s*=\s*@\{.*?\r?\n\}')
    if ($m.Success) { return $m.Value }
    return $null
}
function Set-AdtSessionBlock {
    param([string]$Template, [string]$NewBlock)
    if (-not $NewBlock) { return $Template }
    # MatchEvaluator so the replacement (which contains $adtSession, $(...) etc.) is literal.
    return [regex]::Replace($Template, '(?s)\$adtSession\s*=\s*@\{.*?\r?\n\}',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $NewBlock }, 1)
}
# Field-line prefix: matches BOTH template shapes -
#   MTB  $adtSession block:      "    SoftIdent = '...'"                       (bare field name)
#   GPF wrapper-variable lines: "  [string] $Global:VWG_SoftIdent    = ''"    ([type] $Global:VWG_ prefix)
function Get-FieldLinePrefix { param([string]$Field)
    return "^([ \t]*(?:\[[A-Za-z0-9\[\]]+\][ \t]*)?(?:\`$(?:Global:)?)?(?:VWG_)?$Field(?![A-Za-z0-9_])[ \t]*=[ \t]*)"
}
function Set-SessionField {
    param([string]$Text, [string]$Field, [string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $Text }
    return [regex]::Replace($Text, "(?m)$(Get-FieldLinePrefix $Field)'[^']*'",
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + "'" + $Value + "'" })
}

# Replace the ENTIRE right-hand side of an $adtSession field line (handles '...', "...",
# @(...), $(...)). Used for MTB values pulled from the predecessor (Model.Session).
function Set-SessionValue {
    param([string]$Text, [string]$Field, [string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $Text }
    # FIRST occurrence only: the session/wrapper line comes first in the template. A GLOBAL replace also stamped
    # the value over a SAME-NAMED line the predecessor defines in CUSTOM VARIABLES (e.g. GPF [string]$VWG_SoftIdent
    # with the runtime WoW token) - that line must keep its own value.
    $re = New-Object System.Text.RegularExpressions.Regex ("(?m)$(Get-FieldLinePrefix $Field).*$")
    return $re.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + $Value }, 1)
}

# Normalise a SoftIdent registry path to the package's bitness. The team used to encode
# the hive with a $($VWG_CurrentRegWOW) token / a separate [string]$VWG_SoftIdent variable;
# we don't anymore - SoftIdent lives in $adtSession and the WoW6432Node segment is decided
# purely by the NEW package's architecture:
#   x86  -> path MUST contain ...\SOFTWARE\WoW6432Node\...
#   x64  -> path MUST NOT contain WoW6432Node (some predecessors wrongly had it even on x64)
function Normalize-SoftIdent {
    param([string]$Value, [string]$Arch)
    if (-not $Value) { return $Value }
    # GPF (RegWowHardcode off): their scripts KEEP the runtime token $($VWG_CurrentRegWOW) - value goes through
    # UNTOUCHED (Format-BrandSoftIdent handles generating NEW values in their syntax).
    $hardWow = if (Get-Command Test-PBConvertFlag -ErrorAction SilentlyContinue) { Test-PBConvertFlag 'RegWowHardcode' } else { $true }
    if (-not $hardWow) { return $Value }
    # MTB: drop any leftover token (+ stray space) and hardcode the arch-correct WoW segment.
    $Value = [regex]::Replace($Value, '(?i)\$\(\$?VWG_CurrentRegWO?W\)', '')
    $Value = $Value -replace '\\[ \t]+\{', '\{'
    if ("$Arch" -match '(?i)x86') {
        if ($Value -notmatch '(?i)SOFTWARE\\WoW6432Node\\') {
            $Value = [regex]::Replace($Value, '(?i)(SOFTWARE\\)', '${1}WoW6432Node\', 1)
        }
    } else {
        $Value = [regex]::Replace($Value, '(?i)WoW6432Node\\', '')
    }
    return $Value
}

# Render a SoftIdent VALUE in the brand's house syntax, ready to write as the field's RHS (includes the quotes).
#   GPF : "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\...\Uninstall\{PC} [DisplayVersion = 1.2.3.4]"  (double-quoted,
#         runtime token replaces any explicit WoW6432Node; token inserted after SOFTWARE\ even for x64 - their style).
#   MTB : 'HKLM:\SOFTWARE\[WoW6432Node\]...\Uninstall\{PC} [DisplayVersion=1.2.3.4]'  (single-quoted, arch hardcoded).
function Format-BrandSoftIdent {
    param([string]$Value, [string]$Arch)
    if (-not "$Value".Trim()) { return "''" }
    $hardWow = if (Get-Command Test-PBConvertFlag -ErrorAction SilentlyContinue) { Test-PBConvertFlag 'RegWowHardcode' } else { $true }
    if ($hardWow) { return "'" + (Normalize-SoftIdent -Value $Value -Arch $Arch) + "'" }
    $v = $Value -replace '\\[ \t]+\{', '\{'   # collapse any stray "Uninstall\ {GUID}" space
    if ($v -notmatch '(?i)\$\(\$?VWG_CurrentRegWO?W\)') {   # don't double-insert when the token is already there
        $v = [regex]::Replace($v, '(?i)SOFTWARE\\(WoW6432Node\\)?', 'SOFTWARE\$($VWG_CurrentRegWOW)')
    }
    return '"' + $v + '"'
}

# GPF-only: the PLAIN wrapper form of a SoftIdent value - single-quoted, with NO runtime token and NO WoW6432Node
# segment ("first time / regular under SOFTWARE"). The GandalfClient/Freia gold standard defines $Global:VWG_SoftIdent
# TWICE: once here in the wrapper (plain) and again in CUSTOM APPLICATION VARIABLES with the $($VWG_CurrentRegWOW)
# token (which wins at runtime, being re-assigned after the wrapper). This returns the wrapper value.
function Format-GpfSoftIdentPlain {
    param([string]$Value)
    if (-not "$Value".Trim()) { return "''" }
    $v = $Value
    $v = [regex]::Replace($v, '(?i)\$\(\$?VWG_CurrentRegWO?W\)', '')   # drop the runtime WoW token
    $v = [regex]::Replace($v, '(?i)WoW6432Node\\', '')                # drop any literal WoW6432Node segment
    $v = $v -replace '\\[ \t]+\{', '\{'                               # collapse any stray "Uninstall\ {GUID}" space
    return "'" + ($v -replace "'", "''") + "'"
}

# GPF-only: add (or replace) ONE assignment line inside the CUSTOM APPLICATION VARIABLES BEGIN/END fence. No-op on the
# MTB template (which has no such fence). Idempotent per variable name: re-assigning the same $Global:VWG_* var replaces
# the existing line rather than stacking duplicates.
function Add-GpfCustomVar {
    param([string]$Text, [string]$Line)
    if (-not "$Line".Trim()) { return $Text }
    $m = [regex]::Match($Text, '(?s)(CUSTOM APPLICATION VARIABLES BEGIN[^\r\n]*\r?\n)(.*?)(\r?\n[^\r\n]*CUSTOM APPLICATION VARIABLES END)')
    if (-not $m.Success) { return $Text }   # not a GPF template - leave untouched
    $head = $m.Groups[1].Value; $body = $m.Groups[2].Value; $tail = $m.Groups[3].Value
    $varName = ([regex]::Match($Line, '\$(?:Global:)?(\w+)[ \t]*=')).Groups[1].Value
    if ($varName -and ($body -match ('(?m)^[ \t]*(?:\[[^\]]+\][ \t]*)?\$(?:Global:)?' + [regex]::Escape($varName) + '[ \t]*='))) {
        $newBody = [regex]::Replace($body, '(?m)^[ \t]*(?:\[[^\]]+\][ \t]*)?\$(?:Global:)?' + [regex]::Escape($varName) + '[ \t]*=.*$', $Line.TrimEnd(), 1)
    } else {
        $newBody = $body.TrimEnd("`r", "`n") + "`r`n" + $Line.TrimEnd()
    }
    return $Text.Substring(0, $m.Index) + $head + $newBody + $tail + $Text.Substring($m.Index + $m.Length)
}

# GPF-only: enforce the house SoftIdent convention in BOTH build paths (fresh AND predecessor reuse):
#   WRAPPER ($Global:VWG_SoftIdent in the Wrapper Variables block) = PLAIN value, single-quoted, with NO
#     $($VWG_CurrentRegWOW) token and NO literal WoW6432Node segment (never hardcode the hive - user rule).
#   CUSTOM APPLICATION VARIABLES = a SECOND $Global:VWG_SoftIdent re-assignment carrying the $($VWG_CurrentRegWOW)
#     runtime token. x86 ONLY - a 64-bit package never redirects through WoW6432Node, so the token would be wrong there.
# The custom-vars copy (which WINS at runtime, being assigned after the wrapper) is the source of truth for the value;
# the wrapper is used when there isn't one. Only a SIMPLE quoted literal is touched - a hand-crafted expression-based
# detection (variables, -and/-or, Test-Path) yields no match and is left completely alone. The token copy is added only
# for a real ...\Uninstall\... detection key, never for a VWG\CM branding key (which stays plain, Freia style).
# Idempotent, and a no-op on the MTB template (no CUSTOM APPLICATION VARIABLES fence, different field shape).
# A real registry DETECTION key (…\Uninstall\{GUID} or …\Uninstall\<name>) should always carry the house
# [DisplayVersion=<ver>] suffix, so SCCM/Intune match on name+version. If the value is missing it (e.g. a predecessor
# whose SoftIdent was just a bare ProductCode, or one whose ProductCode we swapped), add it with the NEW package version.
# NEVER touch a VWG\CM branding key (those are name-only tracking keys and must stay without a DisplayVersion), nor a
# value that already has the suffix, nor a non-Uninstall path.
function Add-SoftIdentDisplayVersion {
    param([string]$Value, [string]$Version)
    $v = "$Value"
    if ($v -notmatch '(?i)\\Uninstall\\') { return $v }        # not a real uninstall detection key (e.g. VWG\CM branding)
    if ($v -match '(?i)\[DisplayVersion') { return $v }        # already present
    $ver = "$Version".Trim(); if (-not $ver) { return $v }
    return ($v.TrimEnd() + " [DisplayVersion=$ver]")
}

function Set-GpfSoftIdentTwoPlace {
    param([string]$Text, [string]$Arch, [string]$Version)
    if (-not $Text) { return $Text }
    # HARD brand guard: MTB hardcodes the arch into the hive and has a different field shape - stripping its
    # WoW6432Node segment here would corrupt an MTB x86 detection key. Never run outside GPF.
    if ((Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -ne 'GPF') { return $Text }
    # F40 (GPF team): the $VWG_SoftIdent DECLARATION must always be $Global (some predecessors carry it as a bare
    # "[type] $VWG_SoftIdent = ..." in CUSTOM VARIABLES). Force ONLY VWG_SoftIdent to $Global - other carried VWG_ vars
    # are left exactly as they are. Never matches an already-$Global line (that starts "$Global:VWG_") or a reference.
    $Text = [regex]::Replace($Text, '(?m)^([ \t]*(?:\[[^\]]+\][ \t]*)?)\$VWG_SoftIdent([ \t]*=)', '${1}$Global:VWG_SoftIdent${2}')
    $val = ''
    $cv = [regex]::Match($Text, '(?s)CUSTOM APPLICATION VARIABLES BEGIN(.*?)CUSTOM APPLICATION VARIABLES END')
    if ($cv.Success) {
        $m = [regex]::Match($cv.Groups[1].Value, '(?m)^[ \t]*(?:\[[^\]]+\][ \t]*)?\$(?:Global:)?VWG_SoftIdent[ \t]*=[ \t]*[''"]([^''"]*)[''"]')
        if ($m.Success) { $val = $m.Groups[1].Value }
    }
    if (-not "$val".Trim()) {
        $w = [regex]::Match($Text, "(?m)$(Get-FieldLinePrefix 'SoftIdent')[""']([^""']*)[""']")
        if ($w.Success) { $val = $w.Groups[2].Value }
    }
    if (-not "$val".Trim()) { return $Text }
    # Ensure a real Uninstall detection key carries [DisplayVersion=<new version>] (kept even if the predecessor lacked
    # it / we only swapped the ProductCode). Branding keys (VWG\CM) are left untouched.
    $val = Add-SoftIdentDisplayVersion -Value $val -Version $Version
    $Text = Set-SessionValue -Text $Text -Field 'SoftIdent' -Value (Format-GpfSoftIdentPlain -Value $val)
    if (("$Arch" -match '(?i)x86|32') -and ($val -match '(?i)\\Uninstall\\')) {
        $Text = Add-GpfCustomVar -Text $Text -Line ('[string]$Global:VWG_SoftIdent   =  ' + (Format-BrandSoftIdent -Value $val -Arch $Arch))
    }
    return $Text
}

# GPF-only: the Main-section template scaffold ships TWO log lines - "Start Installation ..." and a bare
# "Installation of ...". The gold standard (Freia/Gandalf) reads "Installation of ... is successful." and puts the
# install command BETWEEN the two logs. With the bare wording, Set-SectionBody's success-anchor never matches and the
# command is appended AFTER both logs, so they read like a duplicated pair. Upgrade the second log to "... is successful."
# so the existing success-anchor logic drops the command between them (matching the gold layout). Idempotent (a line that
# already says "is successful" won't re-match), and a NO-OP on the MTB template (different scaffold wording).
function Set-GpfMainSuccessLog {
    param([string]$Text)
    if (-not $Text) { return $Text }
    # Insert " is successful" right before the closing `."` of the bare "<Action> of $appVendor $appName $appVersion."
    # log. No end-of-line ($) anchor - it fails on CRLF lines (.NET $ matches before \n, and a \r sits before it).
    # Idempotent: once the line reads "...$appVersion is successful.", the "$appVersion\." pattern no longer matches.
    return [regex]::Replace($Text,
        '(Write-ADTLogEntry\b[^\r\n]*"(?:Installation|Uninstallation|Repair) of \$appVendor \$appName \$appVersion)\."',
        '$1 is successful."')
}

# Build the DETECTION key (SoftIdent) automatically from a ProductCode so a FRESH package detects reliably (avoids
# the 0x87D00324 "installed but not detected" trap). Covers:
#   single MSI         -> use the MSI's ProductCode,
#   EXE that wraps MSI -> the ProductCode is in its captured uninstall ('MsiExec /X{GUID}') - pull it out.
# Returns 'HKLM:\SOFTWARE\...\Uninstall\{GUID} [DisplayVersion=<ver>]' (Normalize-SoftIdent later fixes bitness), or
# '' when there's no GUID to key on (the packager then fills the real uninstall key, with the existing warning).
function Get-AutoSoftIdent {
    param([string]$ProductCode, [string]$Version, [string]$SnapshotUninstall, [string]$DisplayVersion)
    $pc = "$ProductCode".Trim()
    if ($pc -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
        $g = [regex]::Match("$SnapshotUninstall", '(?i)\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}')
        if ($g.Success) { $pc = $g.Value }
    }
    if ($pc -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { return '' }
    # The FULL DisplayVersion from the machine's real uninstall entry ALWAYS wins over the package version
    # (e.g. 14.51.36231.0 from ARP vs 14.51.36231 in the package name) - detection must match the registry exactly.
    $v = "$DisplayVersion".Trim(); if (-not $v) { $v = "$Version".Trim() }
    return "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$pc$(if ($v) { " [DisplayVersion=$v]" })"
}

#region Per-user configuration (All-users registry vs Active Setup) -----------------------------------------------
# Two ways to apply PER-USER settings, both auto-generated so the packager doesn't hand-write the fiddly code:
#  - AllUsersReg : Invoke-ADTAllUsersRegistryAction - applies HKCU settings to EVERY existing user + the default
#                  profile at INSTALL time (new users inherit from default). Best for pure registry values.
#  - ActiveSetup : registers an HKLM Active Setup component that runs a PLAIN-PowerShell stub ONCE PER USER at their
#                  next logon (covers users created LATER). Mirrors the team's house structure (Adobe CCDesktopApp):
#                  a "<App>_<Version>_ActiveSetup_Install.ps1" staged in SupportFiles, copied to a persistent dir and
#                  registered via Set-ADTActiveSetup; purged on uninstall.
# Render a captured registry value as a PowerShell literal + its PSADT/native type token, so an auto-filled per-user
# command sets it back with the SAME type. Handles the common kinds; unknown kinds fall back to a quoted string.
function Get-PBRegValueLiteral {
    param($Value, [string]$Kind)
    switch ("$Kind") {
        'DWord'        { return @{ Lit = "$([int]$Value)";   Type = 'DWord' } }
        'QWord'        { return @{ Lit = "$([int64]$Value)"; Type = 'QWord' } }
        'MultiString'  { $parts = @($Value) | ForEach-Object { "'" + ("$_" -replace "'", "''") + "'" }; return @{ Lit = '@(' + ($parts -join ', ') + ')'; Type = 'MultiString' } }
        'Binary'       { $b = @($Value) | ForEach-Object { '0x{0:X2}' -f [int]$_ }; return @{ Lit = '([byte[]]@(' + ($b -join ', ') + '))'; Type = 'Binary' } }
        'ExpandString' { return @{ Lit = "'" + ("$Value" -replace "'", "''") + "'"; Type = 'ExpandString' } }
        default        { return @{ Lit = "'" + ("$Value" -replace "'", "''") + "'"; Type = 'String' } }
    }
}
# Turn captured HKCU items (@{Key;Name;Value;Type}) into per-user registry commands. Style:
#   'ADT'    -> Set-ADTRegistryKey -SID $_.SID ... (for Invoke-ADTAllUsersRegistryAction; HKCU:\ -> HKCU\ for -SID)
#   'Native' -> New-Item + New-ItemProperty on HKCU:\ (plain PowerShell, for the Active Setup stub's user context)
function Get-PBHkcuLines {
    param([object[]]$Items, [ValidateSet('ADT','Native')][string]$Style)
    $lines = New-Object System.Collections.Generic.List[string]
    if ($Style -eq 'Native') {
        foreach ($key in (@($Items) | ForEach-Object { "$($_.Key)" } | Select-Object -Unique)) {
            $lines.Add("New-Item -Path '$key' -Force | Out-Null")
        }
    }
    foreach ($it in @($Items)) {
        $f = Get-PBRegValueLiteral -Value $it.Value -Kind $it.Type
        $nm = "$($it.Name)" -replace "'", "''"
        if ($Style -eq 'ADT') {
            $litPath = ("$($it.Key)" -replace '^(?i)HKCU:\\', 'HKCU\')
            $lines.Add("    Set-ADTRegistryKey -SID `$_.SID -Key '$litPath' -Name '$nm' -Value $($f.Lit) -Type $($f.Type)")   # team house style: -Key (not -LiteralPath) for registry
        } else {
            $lines.Add("New-ItemProperty -Path '$($it.Key)' -Name '$nm' -Value $($f.Lit) -PropertyType $($f.Type) -Force | Out-Null")
        }
    }
    return ($lines -join "`r`n")
}

# The stub file name is shared by the script generator (references it) and the assembler (writes it) so they agree.
function Get-ActiveSetupStubName {
    param([string]$AppName, [string]$Version)
    $appver = ((("$AppName" -replace '[\\/:*?"<>|]', '_').Trim()) + '_' + "$Version".Trim()).Trim('_')
    if (-not $appver) { $appver = 'App' }
    return ($appver + '_ActiveSetup_Install.ps1')
}

# The plain-PowerShell Active Setup stub (NOT PSADT) - runs per-user at logon. Modelled on the team's real stub:
# hides the console, logs under %localappdata%\VWG\Logs, and has a clearly-marked section for the app's HKCU settings.
function Get-ActiveSetupStub {
    param([string]$AppName, [string]$Version, [string]$Vendor, [object[]]$HkcuItems = @())
    $appver = ((("$AppName" -replace '[\\/:*?"<>|]', '_').Trim()) + '_' + "$Version".Trim()).Trim('_')
    if (-not $appver) { $appver = 'App' }
    $v = if ("$Vendor".Trim()) { "$Vendor".Trim() } else { '<Vendor>' }
    $a = if ("$AppName".Trim()) { "$AppName".Trim() } else { '<App>' }
    # The per-user section is either the ACTUAL HKCU settings the snapshot detected (auto-applied per user), or a
    # ready-to-edit placeholder when no snapshot data is available.
    $hkcuSection = if (@($HkcuItems).Count) {
@"
# These HKCU value(s) were DETECTED by the snapshot - they are applied in each user's hive at logon. Review/adjust.
$(Get-PBHkcuLines -Items $HkcuItems -Style 'Native')
"@
    } else {
@'
# A) Import a .reg into HKCU (stage the .reg beside this stub in POST-INSTALLATION; at logon it sits in $ParentDirPath):
#   Start-Process -FilePath "$([Environment]::SystemDirectory)\reg.exe" -ArgumentList "Import `"$ParentDirPath\{APP}_Add_HKCU.reg`"" -WindowStyle Hidden -Wait
# B) Or set values directly under the current user's hive:
#   New-Item -Path 'HKCU:\Software\{VENDOR}\{APP}' -Force | Out-Null
#   Set-ItemProperty -Path 'HKCU:\Software\{VENDOR}\{APP}' -Name '<ValueName>' -Value '<Data>'
'@
    }
    $stub = @'
## Active Setup stub - PLAIN PowerShell (NOT PSADT). Runs ONCE per user at their next logon, in the USER's context,
## from the copy staged under ProgramData. >>> ADD this app's per-user settings in the marked section below. <<<

# Hide the brief console window that appears during Active Setup.
Add-Type -Name Window -Namespace Console -MemberDefinition '
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
function Hide-Console { $p = [Console.Window]::GetConsoleWindow(); [void][Console.Window]::ShowWindow($p, 0) }
Hide-Console

$appname = '{APPVER}'
$LogTime = Get-Date -Format 'MM-dd-yyyy_hh-mm-ss'
$LogDir  = "$env:localappdata\VWG\Logs"
$LogFile = Join-Path $LogDir ($appname + '_ActiveSetup_Install.log')
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$ParentDirPath = Split-Path $script:MyInvocation.MyCommand.Path
"$LogTime : Active Setup started for $appname" >> $LogFile

# =================== PER-USER SETTINGS ===================
{HKCUSECTION}
# =========================================================

"$LogTime : Active Setup finished for $appname" >> $LogFile
'@
    return $stub.Replace('{APPVER}', $appver).Replace('{VENDOR}', $v).Replace('{APP}', $a).Replace('{HKCUSECTION}', $hkcuSection)
}

# Build the POST-INSTALL / POST-UNINSTALL PSADT code + (for Active Setup) the stub for the chosen mode. Vendor/App
# are pre-filled from the package name; only the truly app-specific bits (<ValueName>/<Data>/reg names) stay as
# placeholders so the packager edits the minimum.
function Get-PerUserConfig {
    param([ValidateSet('None','AllUsersReg','ActiveSetup')][string]$Mode, [string]$Vendor, [string]$App, [string]$Version, [object[]]$HkcuItems = @())
    $v = if ("$Vendor".Trim()) { "$Vendor".Trim() } else { '<Vendor>' }
    $a = if ("$App".Trim())    { "$App".Trim() }    else { '<App>' }
    $hasHkcu = @($HkcuItems).Count -gt 0
    $res = [ordered]@{ Mode=$Mode; PostInstall=''; PostUninstall=''; StubName=''; StubText='' }
    switch ($Mode) {
        'AllUsersReg' {
            # Auto-fill with the snapshot-detected HKCU value(s) when available, else a ready-to-edit placeholder line.
            $body = if ($hasHkcu) { Get-PBHkcuLines -Items $HkcuItems -Style 'ADT' }
                    else { "    Set-ADTRegistryKey -SID `$_.SID -Key 'HKCU\Software\$v\$a' -Name '<ValueName>' -Value '<Data>' -Type String" }
            $note = if ($hasHkcu) { "## The value(s) below were DETECTED by the snapshot - review/adjust them." } else { "## EDIT the registry value(s) this app needs under each user's HKCU (auto-redirected per user via -SID)." }
            $res.PostInstall = @"
## Per-user settings applied to EVERY existing user + the default profile (new users inherit). Runs at install time.
$note
Invoke-ADTAllUsersRegistryAction -ScriptBlock {
$body
}
"@
        }
        'ActiveSetup' {
            $stubName       = Get-ActiveSetupStubName -AppName $a -Version $Version
            $res.StubName   = $stubName
            $res.StubText   = Get-ActiveSetupStub -AppName $a -Version $Version -Vendor $v -HkcuItems $HkcuItems
            $res.PostInstall = @"
## Per-user configuration via ACTIVE SETUP: the plain-PowerShell stub below runs ONCE per user at their next logon
## (covers users created later). The stub is staged in SupportFiles - EDIT it to add this app's HKCU settings.
`$userCfgDir = "`$envProgramData\VWG\`$(`$adtSession.AppName)\ActiveSetup"
New-ADTFolder -Path `$userCfgDir
Copy-ADTFile -Path "`$(`$adtSession.DirSupportFiles)\$stubName" -Destination `$userCfgDir
Set-ADTActiveSetup -StubExePath "`$userCfgDir\$stubName" -Description 'User_Registries' -Key `$AppFullName -ExecutionPolicy 'Bypass'
"@
            $res.PostUninstall = @"
## Remove the Active Setup entry (and its per-user replication) + the staged stub on uninstall.
Set-ADTActiveSetup -Key `$AppFullName -PurgeActiveSetupKey
Remove-ADTFolder -Path "`$envProgramData\VWG\`$(`$adtSession.AppName)\ActiveSetup"
"@
        }
    }
    return [pscustomobject]$res
}

# Build the Get-ADTUserProfiles copy loop for the per-user FILES the snapshot detected (Get-SnapshotUserFiles items),
# plus the matching uninstall removal, plus the list of files to STAGE into SupportFiles (Source -> staged Rel under
# SupportFiles\UserProfile\<Scope>\...). Mirrors the team house pattern (Copy-ADTFile per file into each profile).
function Get-PerUserFileCopy {
    param([object[]]$Files)
    $files = @($Files)
    $res = [pscustomobject]@{ PostInstall=''; PostUninstall=''; Staged=@() }
    if (-not $files.Count) { return $res }
    $adtSub = @{ 'Roaming' = 'AppData\Roaming'; 'Local' = 'AppData\Local'; 'LocalLow' = 'AppData\LocalLow' }
    $ins = New-Object System.Collections.Generic.List[string]
    $un  = New-Object System.Collections.Generic.List[string]
    $staged = New-Object System.Collections.Generic.List[object]
    $ins.Add('## Per-user FILES the install wrote (detected by the snapshot) - copied into EVERY user profile (incl. the')
    $ins.Add('## Default profile, so NEW users inherit). The files are staged in SupportFiles by the tool.')
    $ins.Add("[string[]]`$ProfilePaths = Get-ADTUserProfiles | Select-Object -ExpandProperty 'ProfilePath'")
    $ins.Add('foreach ($ProfilePath in $ProfilePaths) {')
    $un.Add('## Remove the per-user files this package copied into each profile.')
    $un.Add("[string[]]`$ProfilePaths = Get-ADTUserProfiles | Select-Object -ExpandProperty 'ProfilePath'")
    $un.Add('foreach ($ProfilePath in $ProfilePaths) {')
    foreach ($f in $files) {
        $scope = "$($f.Scope)"; $rel = "$($f.Rel)".TrimStart('\')
        if (-not $rel) { continue }
        $adt = if ($adtSub.ContainsKey($scope)) { $adtSub[$scope] } else { "AppData\$scope" }
        $relDir = Split-Path $rel -Parent
        $stagedRel = "UserProfile\$scope\$rel"
        $destDir = if ($relDir) { "`$ProfilePath\$adt\$relDir" } else { "`$ProfilePath\$adt" }
        $ins.Add("    Copy-ADTFile -Path `"`$(`$adtSession.DirSupportFiles)\$stagedRel`" -Destination `"$destDir`"")
        $un.Add("    Remove-ADTFile -Path `"`$ProfilePath\$adt\$rel`"")
        $staged.Add([pscustomobject]@{ Source = "$($f.Source)"; Rel = $stagedRel })
    }
    $ins.Add('}'); $un.Add('}')
    $res.PostInstall = ($ins -join "`r`n"); $res.PostUninstall = ($un -join "`r`n"); $res.Staged = $staged.ToArray()
    return $res
}
#endregion

# Whole-file formatting. When PSScriptAnalyzer is available we run Invoke-Formatter
# (AST-based) to fix indentation and stray whitespace and to separate run-together
# ("conjuncted") lines; brace placement is intentionally left alone (CheckOpenBrace=$false)
# so we don't churn the team's authored style. We then trim trailing whitespace and
# collapse 3+ newlines (2+ blank lines) to a single blank line. If PSScriptAnalyzer is
# not installed (or the formatter throws on unparseable input) we fall back to the
# regex-only cleanup, so the tool stays portable.
$script:PBFormatterSettings = @{
    IncludeRules = @('PSUseConsistentIndentation', 'PSUseConsistentWhitespace')
    Rules = @{
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4; Kind = 'space'; PipelineIndentation = 'IncreaseIndentationForFirstPipeline' }
        PSUseConsistentWhitespace  = @{ Enable = $true; CheckInnerBrace = $true; CheckOpenBrace = $false; CheckOpenParen = $true; CheckOperator = $true; CheckPipe = $true; CheckSeparator = $true }
    }
}
# HEADS-UP notices: the FEW important things the packager must SEE after a build (the GUI shows them in a popup), kept
# SEPARATE from the long "review" list nobody reads. Reset per build (by the GUI), appended by the engine, read + shown.
$script:GpfNotices = New-Object System.Collections.Generic.List[string]
function Reset-GpfNotices { $script:GpfNotices = New-Object System.Collections.Generic.List[string] }
function Add-GpfNotice   { param([string]$Text) if (-not $script:GpfNotices) { Reset-GpfNotices }; if ("$Text".Trim()) { [void]$script:GpfNotices.Add("$Text") } }
function Get-GpfNotices  { if ($script:GpfNotices) { return @($script:GpfNotices) } return @() }

# Classify a review line as MUST-SEE (heads-up popup) vs nice-to-know (stays in the review list only). CRITICAL = the
# package could be BROKEN or a rule needs a human decision: a "## REVIEW:" fill-in, a missing install/uninstall command,
# name-based predecessor detection that may not match the installed app, an architecture mismatch, or a source
# type/structure mismatch. Everything else (snapshot-added cleanups, MST notes, style hints) is NOT promoted.
function Test-GpfCriticalReview {
    param([string]$Item)
    if (-not $Item) { return $false }
    return ($Item -match '(?i)(##\s*REVIEW:|\bREVIEW:|no\s+(un)?install(ation)?\s+command|cannot\s+(un)?install|detection\s+is\s+by\s+NAME|does\s+NOT\s+match\s+the\s+installed|real\s+ARP\s+DisplayName|architecture|Source\s+(TYPE|STRUCTURE)|MULTI-COMPONENT|CORRUPT)')
}
# Scan the just-built script + its findings and push the CRITICAL ones into the heads-up notices channel (the review list
# still shows everything - this only PROMOTES the few must-see items to the popup). Deduped.
function Add-CriticalNoticesFromScript {
    param([string]$ScriptText, [bool]$IsPredecessor, [string]$NewProductCode)
    if (-not $ScriptText) { return }
    $found = New-Object System.Collections.Generic.List[string]
    if (Get-Command Get-ReviewItems -EA SilentlyContinue)          { foreach ($r in @(Get-ReviewItems -ScriptText $ScriptText)) { [void]$found.Add("$r") } }
    if (Get-Command Get-ScriptReviewFindings -EA SilentlyContinue) { foreach ($r in @(Get-ScriptReviewFindings -ScriptText $ScriptText -IsPredecessor $IsPredecessor -NewProductCode $NewProductCode)) { [void]$found.Add("$r") } }
    $seen = @{}
    foreach ($r in $found) {
        $t = "$r".Trim(); if (-not $t) { continue }
        if ((Test-GpfCriticalReview -Item $t) -and -not $seen.ContainsKey($t)) { $seen[$t] = $true; Add-GpfNotice $t }
    }
}

# Convert LEADING tabs to spaces (4 each) on every line. PSScriptAnalyzer (Invoke-Formatter) is NOT shipped in the packed
# tool, so on a packager's machine the formatter is skipped and a stray TAB from the template/predecessor renders further
# right than the surrounding space-indented lines (finding: the "...is successful." log sat further right than the install
# command - the command was 7 spaces, the log a TAB+3, and a TAB renders as 8 in ISE). Tab -> 4 spaces aligns them (TAB+3
# -> 7 spaces = the command's indent). SAFE: only the LEADING whitespace run is touched, and here-string interiors
# (@"..."@ / @'...'@) are left byte-for-byte intact (their whitespace is part of the string). No-op when Invoke-Formatter
# already ran (it emits spaces) or when there are no tabs.
function Convert-LeadingTabsToSpaces {
    param([string]$Text)
    if (-not $Text -or ($Text.IndexOf("`t") -lt 0)) { return $Text }
    $lines = $Text -split "`r?`n", -1
    $inHere = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($inHere) {
            # a here-string terminator ("@ or '@) must sit at the START of the line (PowerShell rule)
            if ($ln -match '^[ \t]*("@|''@)') { $inHere = $false }
            continue                                   # never touch here-string interior / terminator line
        }
        if ($ln -match '@("|'')\s*$') { $inHere = $true; continue }   # a here-string opens at end of this line
        $m = [regex]::Match($ln, '^[ \t]+')
        if ($m.Success -and ($m.Value.IndexOf("`t") -ge 0)) {
            $lines[$i] = ($m.Value -replace "`t", '    ') + $ln.Substring($m.Length)
        }
    }
    return ($lines -join "`r`n")
}
# Prefix every (non-blank) line of a body with $Prefix - used to re-indent carried predecessor code to the surrounding
# template's indent (finding #2: "indent carried code 1 or 2 tabs"). Relative indentation inside the body is preserved
# (uniform prefix). SAFE: here-string interiors and their column-0 terminator are NOT prefixed (that whitespace is part
# of the string / the terminator must stay at column 0).
function Add-GpfBodyIndent {
    param([string]$Body, [string]$Prefix)
    if (-not $Body -or -not $Prefix) { return $Body }
    $lines = $Body -split "`r?`n", -1
    $inHere = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($inHere) { if ($lines[$i] -match '^[ \t]*("@|''@)') { $inHere = $false }; continue }   # interior + terminator: leave
        if ($lines[$i].Trim()) { $lines[$i] = $Prefix + $lines[$i] }                                 # prefix real code lines
        if ($lines[$i] -match '@("|'')\s*$') { $inHere = $true }                                      # a here-string opened here
    }
    return ($lines -join "`r`n")
}

# Re-indent a CARRIED predecessor block to sit at $Prefix while PRESERVING its own relative structure.
# Strip-Boilerplate's final .Trim() removes ONLY the first line's leading whitespace, so a naive prefix-every-line
# (Add-GpfBodyIndent) over-indents the already-indented inner lines. This: (1) repairs the trimmed first line up to
# the block's base indent, (2) dedents by the block's common leading-whitespace, (3) indents every code line by
# $Prefix. Here-string interiors are never touched (content must stay byte-exact) and are excluded from the maths.
function Set-CarriedBlockIndent {
    param([string]$Body, [string]$Prefix)
    if (-not $Body) { return $Body }
    $lines = $Body -split "`r?`n", -1
    # classify: code line indices (with leading-whitespace) vs here-string interior/terminator lines (left alone)
    $code = New-Object System.Collections.Generic.List[object]
    $inHere = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($inHere) { if ($lines[$i] -match '^[ \t]*("@|''@)') { $inHere = $false }; continue }
        if ($lines[$i].Trim()) { [void]($lines[$i] -match '^([ \t]*)'); $code.Add(@{ I=$i; W=$Matches[1] }) }
        if ($lines[$i] -match '@("|'')\s*$') { $inHere = $true }
    }
    if ($code.Count -eq 0) { return $Body }
    if ($code.Count -ge 2) {
        $restMinW = ($code[1..($code.Count-1)] | Sort-Object { $_.W.Length } | Select-Object -First 1).W
        if ($code[0].W.Length -lt $restMinW.Length) { $lines[$code[0].I] = $restMinW + $lines[$code[0].I]; $code[0].W = $restMinW }
    }
    $lcp = ($code | Sort-Object { $_.W.Length } | Select-Object -First 1).W
    foreach ($x in $code) { while ($lcp.Length -gt 0 -and -not $x.W.StartsWith($lcp)) { $lcp = $lcp.Substring(0, $lcp.Length-1) } }
    foreach ($x in $code) {
        $rest = if ($lcp.Length) { $lines[$x.I].Substring($lcp.Length) } else { $lines[$x.I] }
        $lines[$x.I] = $Prefix + $rest
    }
    return ($lines -join "`r`n")
}

# Align the TEMPLATE scaffold log lines ("Start <Action> ..." and "<Action> of ... [is successful]." with -Source
# $adtSession.DeployAppScriptFriendlyName) to the indent of the install/uninstall/repair COMMAND next to them, so the
# log pair and the command it wraps share ONE indent. Needed because a changed template can leave the "successful" log
# further right than the command (finding: that line "went too much further"). SAFE: ONLY these recognisable template
# scaffold log lines are re-indented - never the command, never predecessor/custom code, never here-string interiors.
function Align-GpfScaffoldLogs {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $scaffRe = "(?i)^[ \t]*Write-ADTLogEntry\b.*-Message\s+['`"](?:Start\s+(?:Installation|Uninstallation|Repair)\b|(?:Installation|Uninstallation|Repair)\s+of\b).*-Source\s+\`$adtSession\.DeployAppScriptFriendlyName"
    $cmdRe   = '(?i)^[ \t]*(?:\$\w+\s*=\s*)?(?:Start-ADTMsiProcess|Start-ADTProcess|Execute-MSI|Execute-Process|Start-ADTMspProcess)\b'
    $lines = $Text -split "`r?`n", -1
    $inHere = $false
    $isCmd  = { param($l) $l -match $cmdRe }
    $isCode = { param($l) $t = "$l".Trim(); $t -and ($t -notmatch '^#') -and ($t -notmatch '^[{}()]+$') -and ($l -notmatch $scaffRe) }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($inHere) { if ($lines[$i] -match '^[ \t]*("@|''@)') { $inHere = $false }; continue }
        if ($lines[$i] -match '@("|'')\s*$') { $inHere = $true; continue }
        if ($lines[$i] -notmatch $scaffRe) { continue }
        # prefer the nearest install COMMAND's indent (within 5 lines, down then up); else the nearest plain code line.
        $target = $null
        foreach ($pick in @($isCmd, $isCode)) {
            for ($j = $i + 1; $j -lt [Math]::Min($lines.Count, $i + 6); $j++) { if (& $pick $lines[$j]) { $target = [regex]::Match($lines[$j], '^[ \t]*').Value; break } }
            if ($null -eq $target) { for ($j = $i - 1; $j -ge [Math]::Max(0, $i - 6); $j--) { if (& $pick $lines[$j]) { $target = [regex]::Match($lines[$j], '^[ \t]*').Value; break } } }
            if ($null -ne $target) { break }
        }
        if ($null -ne $target) { $lines[$i] = $target + $lines[$i].TrimStart() }
    }
    return ($lines -join "`r`n")
}
function Format-OutputScript {
    param([string]$Text)
    # Strip a stray leading BOM character (U+FEFF): Read-FileSmart decodes the BOM'd
    # template into the string, leaving a literal U+FEFF before "<#" that stops the
    # parser seeing the comment-based help block. The file's real BOM is re-added at save.
    $Text = $Text.TrimStart([char]0xFEFF)
    # Normalise INVISIBLE characters a predecessor may carry (Word-pasted comments/strings, copied text) that PowerShell
    # rejects as an "invalid character" at parse time: non-breaking spaces -> a normal space; zero-width chars, LTR/RTL
    # direction marks and any stray INLINE BOM -> removed. Done BEFORE Invoke-Formatter (which also chokes on a NBSP).
    $Text = [regex]::Replace($Text, '[\u00A0\u2007\u202F]', ' ')                       # NBSP variants -> space
    $Text = [regex]::Replace($Text, '[\u200B\u200C\u200D\u200E\u200F\u2060\uFEFF]', '')   # zero-width / direction marks / inline BOM -> gone
    # SAFETY NET: the internal PRE-INSTALL dialogs-split marker must NEVER reach a shipped script. Set-SectionBody normally
    # consumes it, but it can leak when a body carrying it is reused (e.g. a predecessor Pre-Uninstall section folded into
    # the generated uninstall-previous block). Remove the whole marker line here, unconditionally.
    $Text = [regex]::Replace($Text, '(?m)^[ \t]*#__PB_DIALOGS_SPLIT__[ \t]*\r?\n?', '')
    # Normalise to CRLF first: assembled scripts mix \r\n and \n (template + injected
    # bodies), and Invoke-Formatter refuses input with mixed line endings.
    $Text = [regex]::Replace($Text, "\r\n?|\n", "`r`n")
    if (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue) {
        try   { $Text = Invoke-Formatter -ScriptDefinition $Text -Settings $script:PBFormatterSettings }
        catch { Write-Log "Invoke-Formatter failed; using light cleanup. $($_.Exception.Message)" Warning }
    }
    # Always normalise leading tabs -> spaces (packager machines have no PSScriptAnalyzer, so the formatter above is
    # skipped there and a stray tab would render further right than the space-indented lines around it).
    $Text = Convert-LeadingTabsToSpaces -Text $Text
    # Align the template's "Start/…successful" scaffold log lines to the install command's indent (a changed template can
    # leave the "successful" log further right than the command).
    $Text = Align-GpfScaffoldLogs -Text $Text
    # GPF house style: the v4 "## MARK: <Phase>" fences are the ONLY section banners (matches their hand-authored
    # packages, e.g. Freia). The template also carries the older "#*====PHASE BEGIN/END====" markers, used purely as
    # injection anchors during the build; strip them from the FINAL output so the script isn't double-bannered
    # (team finding: duplicate BEGIN/END banner lines in every section, incl. CUSTOM APPLICATION VARIABLES/FUNCTIONS).
    if ((Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') {
        $Text = [regex]::Replace($Text, '(?im)^[ \t]*#\*=+\s*(?:CUSTOM APPLICATION (?:VARIABLES|FUNCTIONS)|PRE-INSTALLATION|MAIN-INSTALLATION|POST-INSTALLATION|PRE-UNINSTALLATION|MAIN-UNINSTALLATION|POST-UNINSTALLATION|PRE-REPAIR|MAIN-REPAIR|POST-REPAIR)\s+(?:BEGIN|END)\s*=+[^\r\n]*\r?\n?', '')
        # GPF: snapshot-captured registry keys carry a LITERAL \WOW6432Node\ (seen on the 64-bit test machine). GPF
        # house style uses the runtime token $($VWG_CurrentRegWOW) (their extension resolves it to "Wow6432Node\" on
        # 64-bit OS, "" on 32-bit) so the SAME key is correct on both (finding: "WOW6432node hardcoded for GPF").
        # Single-quoted key literals are switched to double quotes so the token interpolates; the token already
        # includes its trailing backslash, so "...\WOW6432Node\..." becomes "...\$($VWG_CurrentRegWOW)...".
        $Text = [regex]::Replace($Text, "(?i)'([^'\r\n]*)\\WOW6432Node\\([^'\r\n]*)'",
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) '"' + $m.Groups[1].Value + '\$($VWG_CurrentRegWOW)' + $m.Groups[2].Value + '"' })
        $Text = [regex]::Replace($Text, '(?i)\\WOW6432Node\\', '\$($VWG_CurrentRegWOW)')
        # Copy-ADTFile from an EXTERNAL source ($env* path, e.g. a log file that may not exist) must be Test-Path
        # guarded (v4 Copy-ADTFile errors on a missing source; finding: "Copy-ADTfile required test-path"). A line
        # that already starts with "if (Test-Path" is naturally skipped (the anchor requires a BARE Copy-ADTFile).
        # Package-payload copies ($dirFiles/DirFiles/SupportFiles/ScriptDirectory) always exist and are left alone.
        # NB: no "$" line-end anchor - in multiline mode "$" sits before \n with the \r in between (CRLF), so it only
        # matched the final line. "[^\r\n]*" naturally stops at the line end and TrimEnd() drops trailing whitespace.
        $Text = [regex]::Replace($Text, '(?im)^([ \t]*)(Copy-ADT(?:File|Folder)[ \t]+-Path[ \t]+(?<src>"[^"\r\n]*"|''[^''\r\n]*'')[^\r\n]*)',
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($m)
                $src = $m.Groups['src'].Value
                if ($src -notmatch '(?i)\$\(?\$?env\w+') { return $m.Value }                       # not an external $env source
                if ($src -match '(?i)dirfiles|supportfiles|scriptdirectory') { return $m.Value }   # package payload - always present
                # ALREADY GUARDED: a predecessor (v4.1.5+) may already wrap this copy in an OUTER "If (Test-Path -Path
                # <same src>) { ... }", with the bare Copy on its own line inside. Adding a second Test-Path here would
                # DOUBLE the guard (finding: "Test-Path added twice"). If the lines just above already Test-Path the SAME
                # source, leave the copy bare.
                $before = $Text.Substring(0, $m.Index)
                $prev = (($before -split "\r?\n") | Select-Object -Last 3) -join "`n"
                $srcInner = "$src".Trim('"', "'")
                if (($prev -match '(?i)Test-Path') -and ($prev -match [regex]::Escape($srcInner))) { return $m.Value }
                $m.Groups[1].Value + "if (Test-Path -Path $src) { " + $m.Groups[2].Value.TrimEnd() + ' }'
            })
    }
    # Trim trailing whitespace on EVERY line (incl. whitespace-only lines) and re-join with
    # CRLF. A "(?m)[ \t]+$" regex misses these because $ sits before \n with the \r in
    # between, so the trailing spaces are not immediately before the anchor.
    $Text = (($Text -split "\r?\n") | ForEach-Object { $_.TrimEnd() }) -join "`r`n"
    # Collapse 3+ newlines (2+ blank lines) down to a single blank line.
    $Text = [regex]::Replace($Text, "(\r\n){3,}", "`r`n`r`n")
    # Final catch-all: a SoftIdent detection key must never read "...\Uninstall\ {GUID}" (stray space after the
    # backslash - team finding). A real Uninstall subkey never starts with a space, so this is always safe.
    $Text = [regex]::Replace($Text, '(?i)(\\Uninstall)\\[ \t]+\{', '${1}\{')
    # Safety net: -IfEmpty is NOT a valid v4 Remove-ADTFolder parameter (verified v4.1.5) but can survive inside a
    # predecessor block that was preserved verbatim (never run through the v3->v4 converter). Rewrite the simple
    # "Remove-ADTFolder [-Path|-LiteralPath] <path> -IfEmpty" form to the Test-Path + emptiness-guarded removal.
    $Text = [regex]::Replace($Text, '(?im)^([ \t]*)Remove-ADTFolder[ \t]+(?:-(?:LiteralPath|Path)[ \t]+)?("[^"]+"|''[^'']+''|\$\S+)[ \t]+-IfEmpty\b[^\r\n]*', {
        param($m)
        $ind = $m.Groups[1].Value; $p = $m.Groups[2].Value
        # GPF team house style: single If with -PathType Container AND (Get-ChildItem -Force | Measure-Object).Count -eq 0.
        @(
            "${ind}if ((Test-Path -Path $p -PathType Container) -and ((Get-ChildItem $p -Force | Measure-Object).Count -eq 0))"
            "${ind}{"
            "${ind}    Remove-ADTFolder -Path $p"
            "${ind}}"
        ) -join "`r`n"
    })
    return $Text
}
function Set-TemplatePlaceholders {
    param([string]$Text, [hashtable]$NewPkg)
    $Text = $Text.Replace('{ScriptDate}', (Get-Date -Format 'yyyy-MM-dd'))
    if ($NewPkg.Author) { $Text = $Text.Replace('{ScriptAuthor}', (Format-AuthorName $NewPkg.Author)) }
    $Text = $Text.Replace('{Revision}', "$($NewPkg.Revision)")
    $Text = $Text.Replace('{Action}',   'New package')
    return $Text
}

# Author display name, GPF house style: NO comma. The request/matrix often carries "Last, First"
# ("Prajapati, Sunil"); the team writes it plainly ("Prajapati Sunil"). Strip commas, collapse spaces.
function Format-AuthorName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    return (($Name -replace ',', ' ') -replace '\s+', ' ').Trim()
}

# Fill the GPF wrapper-variable line for $Field ONLY when its current value is blank or an
# unreplaced '{placeholder}'. Never overwrites a real value (Model.Session / snapshot fills win).
function Set-WrapperIfBlank {
    param([string]$Text, [string]$Field, [string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $Text }
    # "blank"/"BLANK" is a placeholder some predecessors carry (e.g. VWG_Portfv = 'blank') - treat it as empty too, so
    # it gets filled with the real value (F22). A {placeholder} and '' were already treated as blank.
    $rx = "(?m)$(Get-FieldLinePrefix $Field)'(?:\{[^}]*\}|[ \t]*|(?i:blank))'"
    return [regex]::Replace($Text, $rx,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + "'" + $Value + "'" })
}

# Guarantee the GPF wrapper block never ships blank/placeholder values that the team flagged
# (Freia/Gandalf test cases: SoftinstTyp='{Typ}', SoftIdent='', Portfv='', FreeSpace='' -> [int32]'' crashes).
# Only fills what is still blank, so predecessor-carried / snapshot values are preserved. GPF-only
# (these wrapper lines don't exist in the MTB template, so the replaces are no-ops there anyway).
function Set-GpfWrapperDefaults {
    param([string]$Text, [hashtable]$NewPkg, [bool]$IsMsi)
    if ((Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -ne 'GPF') { return $Text }
    $vendor = "$($NewPkg.Vendor)"
    $full   = "$($NewPkg.Vendor)_$($NewPkg.AppName)_$($NewPkg.Arch)_$($NewPkg.Version)-$($NewPkg.Revision)_$($NewPkg.Lang)"
    # SoftinstTyp: 'MSI' for an MSI install, else 'Legacy' (exe/loose files). Replaces the '{Typ}' token.
    $Text = Set-WrapperIfBlank -Text $Text -Field 'SoftinstTyp' -Value ($(if ($IsMsi) { 'MSI' } else { 'Legacy' }))
    # Portfv = the vendor (team house style: $appVendor). FORCE it to the current vendor - some predecessors carry a
    # 'blank'/stale Portfv (F22); the house style is always $appVendor. Only fall back to fill-if-blank if we somehow
    # have no vendor, so we never write an empty Portfv.
    if ("$vendor".Trim()) { $Text = Set-SessionValue -Text $Text -Field 'Portfv' -Value "'$vendor'" }
    else { $Text = Set-WrapperIfBlank -Text $Text -Field 'Portfv' -Value $vendor }
    # AppAddInfo01-04: team house style keeps these as 'NA' unless a packager sets them. Fill any blank/'blank'/{ph}
    # value with 'NA' (F22) - a real customised value is preserved.
    foreach ($n in '01','02','03','04') { $Text = Set-WrapperIfBlank -Text $Text -Field "AppAddInfo$n" -Value 'NA' }
    # OrderNumber = the AES/RITM number.
    $Text = Set-WrapperIfBlank -Text $Text -Field 'OrderNumber' -Value "$($NewPkg.Ritm)"
    # Required install disk space (MB): from the source payload when known, else a safe floor (300, matches house default).
    $Text = Set-WrapperIfBlank -Text $Text -Field 'FreeSpace' -Value ($(if ($NewPkg.FreeSpace) { "$($NewPkg.FreeSpace)" } else { '300' }))
    # Uninstall free space is FORCED to 200 for every package (team finding: EQS hit issues with higher uninstall free
    # space). Overrides any value carried from the predecessor (Set-SessionValue replaces the whole RHS, not fill-if-blank).
    $Text = Set-SessionValue -Text $Text -Field 'FreeSpaceUninst' -Value "'200'"
    # SoftIdent: an MSI's detection comes from its Uninstall\{ProductCode} key (filled elsewhere / flagged for review).
    # F47: for a Legacy/exe package with NO verified key (no snapshot GUID captured), write a best-guess detection in the
    # real house FORMAT keyed on the app name + package version - '...\Uninstall\<AppName> [DisplayVersion=<version>]' -
    # so the wrapper never ships an unusable detection AND the semantic review flags it (subkey == app name) for the
    # packager to install the EXE, read the real uninstall key, and fill it. (The old VWG\CM\<full> tracking path was NOT
    # a real detection key and slipped past the review because its subkey isn't under \Uninstall\<app>.)
    if (-not $IsMsi) {
        $siApp = "$($NewPkg.AppName)".Trim(); $siVer = "$($NewPkg.Version)".Trim()
        $siGuess = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$siApp$(if ($siVer) { " [DisplayVersion=$siVer]" })"
        $Text = Set-WrapperIfBlank -Text $Text -Field 'SoftIdent' -Value $siGuess
    }
    return $Text
}

##############################################################
# Standard install/uninstall/repair command sets per installer type. Ported from the
# reference CommandBuilder, adapted to PSADT v4 + the team's template conventions
# ($adtSession.DirFiles path, -RepairMode on repair). Modes: SingleMSI, SingleEXE,
# LooseFiles, Multiple. Each returns @{ MainInstall; MainUninstall; MainRepair; PreRepair }.
##############################################################
function Get-MsiCommandSet {
    param([string]$Msi, [string]$Mst, [string]$ProductCode, [switch]$NoMst)
    $ProductCode = "$ProductCode".Trim()   # a leading/trailing space (e.g. from a parsed SoftIdent GUID) breaks "msiexec /x { GUID}"
    # F27/F29: when the packager opted OUT of MST generation AND there is no source MST to reuse, install the MSI PLAIN
    # (no -Transform). $NoMst forces that. Otherwise: use the given $Mst (a reused SOURCE mst, or a specific name), else
    # default to the MSI's path with a .mst extension (the built transform - preserves any subfolder under DirFiles).
    if ($NoMst) { $Mst = '' }
    elseif (-not $Mst -and $Msi) { $Mst = [IO.Path]::ChangeExtension($Msi, '.mst') }
    $install = if ($Mst) {
        "Start-ADTMsiProcess -Action 'Install' -FilePath `"`$(`$adtSession.DirFiles)\$Msi`" -Transform `"`$(`$adtSession.DirFiles)\$Mst`""
    } else {
        "Start-ADTMsiProcess -Action 'Install' -FilePath `"`$(`$adtSession.DirFiles)\$Msi`""
    }
    if ($ProductCode) {
        $uninstall = "Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '$ProductCode'"
        $repair    = "Start-ADTMsiProcess -Action 'Repair' -RepairMode 'Repair' -ProductCode '$ProductCode'"
    } else {
        $uninstall = "Start-ADTMsiProcess -Action 'Uninstall' -FilePath `"`$(`$adtSession.DirFiles)\$Msi`""
        $repair    = "Start-ADTMsiProcess -Action 'Repair' -RepairMode 'Repair' -FilePath `"`$(`$adtSession.DirFiles)\$Msi`""
    }
    return @{ MainInstall = $install; MainUninstall = $uninstall; MainRepair = $repair; PreRepair = '' }
}
# Scan a built script for items the packager MUST review (## REVIEW: lines we emit where info was missing).
# Returns the clear messages (without the marker) so the GUI can list them - not a buried "TODO".
function Get-ReviewItems {
    param([string]$ScriptText)
    if (-not $ScriptText) { return @() }
    return @([regex]::Matches($ScriptText, '(?m)^\s*##\s*REVIEW:\s*(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
}
# SEMANTIC review pass: things that PARSE fine but are likely WRONG for the new version / wrong on v4, which
# the packager must look at. These are NOT '## REVIEW:' markers in the script - they are derived by inspecting
# the built script, so they catch carried-over predecessor identifiers and v4 lifecycle traps. Returns clear
# messages. Re-run live each time (so fixing the script removes the finding).
function Get-ScriptReviewFindings {
    param([string]$ScriptText, [bool]$IsPredecessor = $false, [string]$NewProductCode = '')
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $ScriptText) { return $out.ToArray() }
    $guid = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'

    # 1. Detection key (SoftIdent) carries a product-code GUID from the predecessor: the version was swapped but
    #    the GUID is per-release (MSI ProductCode / Inno '_is1'), so detection will mis-fire if left as-is.
    if ($IsPredecessor) {
        # field-line-prefix so BOTH shapes are seen (MTB "SoftIdent =" and GPF "[string] $Global:VWG_SoftIdent =");
        # quote-agnostic (GPF values are double-quoted for the runtime WoW token)
        $m = [regex]::Match($ScriptText, "(?im)$(Get-FieldLinePrefix 'SoftIdent')['`"][^'`"]*($guid(?:_is1)?)")
        if ($m.Success) {
            $siPc = $m.Groups[2].Value
            # If the SoftIdent product code already EQUALS the NEW package's ProductCode, it was correctly swapped -
            # it is NOT the predecessor's, so don't flag it (was a false "carried from predecessor" warning). Only warn
            # when it differs from the new PC (or the new PC is unknown).
            $normNew = "$NewProductCode".Trim().Trim('{','}').ToLower()
            $normSi  = ($siPc -replace '(?i)_is1$','').Trim().Trim('{','}').ToLower()
            if (-not ($normNew -and $normSi -eq $normNew)) {
                $out.Add("Detection key (SoftIdent) uses product code '$siPc' carried from the PREDECESSOR - verify/replace it for the new version after the test install (check the real uninstall key's ProductCode/name/DisplayVersion; MSI ProductCodes and Inno '_is1' keys change every release).")
            }
        }
    }

    # 1b. Predecessor uninstall-previous detection resolved by NAME, not ProductCode (F9). Either the predecessor's real
    #     ARP DisplayName was recovered from its SoftIdent, or - when the SoftIdent had no usable name - it FELL BACK to
    #     the parsed package AppName, which usually does NOT match the installed app's DisplayName. Name-based detection
    #     of the predecessor must always be confirmed against the real Programs-and-Features entry; the bare-AppName
    #     fallback is flagged more strongly (this was previously unflagged - the "appname fetched as a normal name" miss).
    if ($IsPredecessor) {
        $upg   = [regex]::Match($ScriptText, '(?s)#Upgrade\b.*?(?:\r?\n\}|\z)')
        $scope = if ($upg.Success) { $upg.Value } else { '' }
        $appNm = [regex]::Match($ScriptText, "(?im)^\s*AppName\s*=\s*'([^']*)'").Groups[1].Value.Trim()
        foreach ($nm in [regex]::Matches($scope, '(?im)Get-ADTApplication\s+-Name\s+["'']([^"'']+)["'']')) {
            $nmVal = $nm.Groups[1].Value.Trim()
            if ($appNm -and ($nmVal -ieq $appNm)) {
                $out.Add("Predecessor uninstall detection uses the bare package name (Get-ADTApplication -Name '$nmVal') - a FALLBACK because the predecessor's SoftIdent had no usable DisplayName. This likely does NOT match the installed app's real ARP DisplayName (e.g. Inno apps register as '<Name>_<version>'). CHECK AND FILL: read the predecessor's real Programs-and-Features DisplayName and set it here, or the old version won't be detected/removed before install.")
            } else {
                $out.Add("Predecessor uninstall detection is by NAME (Get-ADTApplication -Name '$nmVal', taken from the predecessor's SoftIdent) - confirm it matches the installed app's real ARP DisplayName EXACTLY; a mismatch means the old version is not detected/removed before install.")
            }
        }
    }

    # 1c. F52: installation progress bar carried from the predecessor. It's enabled to match the predecessor, but an
    #     app's install behaviour (duration, prompts) can change version to version - flag it so the packager verifies
    #     during source validation & testing that the bar still makes sense for this version.
    if ($IsPredecessor -and [regex]::IsMatch($ScriptText, '(?im)^[ \t]*(?<!#)Show-(?:ADT)?InstallationProgress\b')) {
        $out.Add("Installation progress bar is ENABLED (carried from the predecessor). App install behaviour can vary version to version - verify during source validation & testing that showing the progress bar is still appropriate for this version (disable it if the install is now silent/short).")
    }

    # 1d. F54: ProcToBlock (processes blocked during install). When the predecessor carried NO ProcToBlock and ProcToClose
    #     had nothing to mirror either, the current package ships an empty block-list. Surface it so the packager decides
    #     whether this app needs process-blocking during install, rather than silently leaving it empty.
    if ($IsPredecessor) {
        $pbLine = [regex]::Match($ScriptText, "(?im)$(Get-FieldLinePrefix 'ProcToBlock')(.+?)[ \t]*$")
        if ($pbLine.Success -and -not [regex]::IsMatch($pbLine.Groups[2].Value, "'[^']+'|`"[^`"]+`"")) {
            $out.Add("ProcToBlock (apps blocked from launching DURING install) is empty - the predecessor didn't set it and there was nothing to mirror from ProcToClose. Confirm this app doesn't need any process blocked during install, or add the process name(s); leaving it empty means users can launch the app mid-install.")
        }
    }

    # 1e. F57-59: predecessor helper files. A carried predecessor often RUNS a helper script/file out of its own
    #     SupportFiles (e.g. Bentley's sc-uninstall.ps1 in post-uninstallation). Predecessor reuse carries the deployment
    #     SCRIPT but NOT the helper files sitting beside it, so the reference dangles. Detect any file referenced via the
    #     SupportFiles dir ($adtSession.DirSupportFiles / $dirSupportFiles / a literal "SupportFiles\<name>") and SUGGEST
    #     the packager copy each into THIS package's SupportFiles\ (identified during source validation).
    if ($IsPredecessor) {
        $sfNames = New-Object System.Collections.Generic.List[string]
        $sfRx = '(?i)(?:\$(?:adtSession\.)?[Dd]irSupportFiles|\$\([^)]*[Dd]irSupportFiles[^)]*\)|\bSupportFiles)\\+([\w .\-]+\.(?:ps1|cmd|bat|vbs|exe|reg|msi|mst))'
        foreach ($mm in [regex]::Matches($ScriptText, $sfRx)) {
            $fn = $mm.Groups[1].Value.Trim()
            if ($fn -and -not ($sfNames -contains $fn)) { [void]$sfNames.Add($fn) }
        }
        if ($sfNames.Count) {
            $out.Add("The package runs helper file(s) from SupportFiles that the predecessor carried: $($sfNames -join ', '). Predecessor reuse copies the deployment SCRIPT but NOT these helper files - copy each one into THIS package's SupportFiles\ folder (identify them during source validation), or the run will fail with 'file not found'.")
        }
    }

    # 2. v4 variable scope. If the build auto-moved the offending lines (marker present), just ask to VERIFY.
    #    If something STILL reads $adtSession.DeploymentType in the variables block (the auto-fix skips multi-line
    #    assignments), tell the user to move it - it is EMPTY there on v4.
    if ($ScriptText -match '\[Package Builder\] moved from the variables block') {
        $out.Add('Some variables were AUTO-MOVED from the CUSTOM VARIABLES block into the Install/Uninstall/Repair PRE-sections (they read the live session - DeploymentType / ADT $env* - empty in the variables block on v4). Verify the resulting paths / log names look right.')
    }
    $cv = [regex]::Match($ScriptText, '(?s)CUSTOM APPLICATION VARIABLES BEGIN(.*?)CUSTOM APPLICATION VARIABLES END')
    if ($cv.Success -and ($cv.Groups[1].Value -match '\$adtSession\.DeploymentType')) {
        $out.Add('A variable still in the CUSTOM VARIABLES block reads $adtSession.DeploymentType, which is EMPTY there on PSADT v4 (only set inside the Install/Uninstall/Repair functions). Move that line into the relevant function (the auto-fix skips multi-line assignments), or the path/log name will be blank.')
    }

    # 3. Response/answer file (INF/ISS) carried from the predecessor - usually embeds the old version/paths and
    #    must be regenerated for the new build.
    if ($IsPredecessor) {
        # Only flag a .inf/.iss that's actually used in an install command / argument (not one mentioned in a
        # comment or a log-file name), to avoid noise.
        $inf = [regex]::Match($ScriptText, '(?im)^(?:(?!#).)*(?:Start-ADTProcess|Execute-Process|-ArgumentList|-Parameters|LOADINF|/f1|inputFile|-f\b).*?([\w.\-]+\.(?:inf|iss))\b')
        if ($inf.Success) {
            $out.Add("The install references the answer/response file '$($inf.Groups[1].Value)' from the predecessor - regenerate it for the new version if it is version- or environment-specific (record files often embed the old version or machine paths).")
        }
    }

    # 4. FRESH package (no predecessor): the detection key (SoftIdent) is resolved from the app NAME, not from a
    #    verified registry key. If it doesn't reference the MSI ProductCode (or the subkey is just the app name /
    #    an unresolved placeholder) it likely won't match what the installer writes -> SCCM 0x87D00324 / Intune
    #    "installed but not detected". Surface this so the packager verifies detection BEFORE deploying.
    if (-not $IsPredecessor) {
        $sm  = [regex]::Match($ScriptText, "(?im)$(Get-FieldLinePrefix 'SoftIdent')['`"]([^'`"]*)['`"]")
        $si  = if ($sm.Success) { $sm.Groups[2].Value } else { '' }
        $app = [regex]::Match($ScriptText, "(?im)^\s*AppName\s*=\s*'([^']*)'").Groups[1].Value
        $hasMsiPc = [regex]::IsMatch($ScriptText, "(?is)MAIN-UNINSTALLATION BEGIN.*?-ProductCode\s*'$guid'")
        $siGuid   = [regex]::IsMatch($si, $guid)
        $subKey   = ([regex]::Match($si, '(?i)\\Uninstall\\([^\[\]\r\n]+?)\s*(?:\[|$)')).Groups[1].Value.Trim()
        if (-not "$si".Trim()) {
            $out.Add("Detection key (SoftIdent) is EMPTY on this fresh package - SCCM/Intune will have nothing to detect with. Set the MSI ProductCode, or the real HKLM ...\Uninstall\<key> the installer writes, before publishing.")
        } elseif ($si -match '<[^>]+>') {
            $out.Add("Detection key (SoftIdent) still contains an unresolved placeholder ('$si') - replace it with the real ProductCode / uninstall registry key or detection will fail (0x87D00324 'installed but not detected').")
        } elseif ($hasMsiPc -and -not $siGuid) {
            $out.Add("Fresh MSI package: the detection key (SoftIdent) does NOT use the MSI ProductCode. Verify it matches what the installer writes to HKLM ...\Uninstall (MSI uses the ProductCode GUID as the subkey) - a mismatch causes SCCM 0x87D00324 'installed but not detected'.")
        } elseif ($subKey -and $app -and ($subKey -ieq $app)) {
            $out.Add("Detection key (SoftIdent) uses the bare app name ('$subKey') as the uninstall subkey - a best-guess from the package name (no snapshot was captured to read the real key). It likely does NOT match what the installer writes. CHECK AND FILL before publishing: install the app, open the real HKLM ...\Uninstall\<key> the installer creates, and copy its exact subkey name + DisplayVersion here (MSI: use the ProductCode GUID) - otherwise detection fails (0x87D00324 'installed but not detected').")
        }
    }
    return $out.ToArray()
}

# PREDECESSOR REUSE REPORT - the presentable, two-part summary an engineer reads after a reuse build. The whole point
# is to let a packager TRUST the automation and only touch the few unknowns:
#   .Done  = what was changed AUTOMATICALLY. Each line is VERIFIED against the built script (we never claim a swap we
#            can't see in the output), so the list is honest. Plain language, no jargon.
#   .Check = the handful of things a human must confirm/fill (the "unknowns") - carried detection code, answer files,
#            a source that doesn't match the predecessor's shape, a leftover old name. Each says WHY it matters.
# Derived live from the model + new package + the built script (re-runnable: fixing the script clears a Check item).
function Get-PredecessorReport {
    param([hashtable]$Model, [hashtable]$NewPkg, [string]$ScriptText, [bool]$AddUninstallPrevious = $true, [string]$MismatchText = '')
    $done  = New-Object System.Collections.Generic.List[string]
    $check = New-Object System.Collections.Generic.List[string]
    if (-not $Model -or -not $ScriptText) { return @{ Done = $done.ToArray(); Check = $check.ToArray() } }
    $has    = { param($s) ($s) -and ($ScriptText.IndexOf("$s", [StringComparison]::OrdinalIgnoreCase) -ge 0) }
    $predVer = "$($Model.Identity.Version)"; $newVer = "$($NewPkg.Version)"
    # MAIN-INSTALL section text (to tell a real leftover in an install command from a mention in the uninstall-previous block)
    $mainInstall = ([regex]::Match($ScriptText, '(?is)MAIN-INSTALLATION BEGIN(.*?)MAIN-INSTALLATION END')).Groups[1].Value

    # ---- DONE (auto) -------------------------------------------------------------------------------------------
    $done.Add("Reused your '$($Model.Identity.FullName)' package as the template - all its custom install/uninstall logic was carried over, then retargeted to this build.")
    if ($newVer) { $done.Add("Package identity set to the new build: $($NewPkg.Vendor) $($NewPkg.AppName), $($NewPkg.Arch), $($NewPkg.Lang), version $newVer.") }
    if ($predVer -and $newVer -and $predVer -ne $newVer) {
        $n = ([regex]::Matches($ScriptText, [regex]::Escape($newVer))).Count
        $done.Add("Version updated everywhere: $predVer -> $newVer (the new version now appears in $n place$(if($n -ne 1){'s'}) - folder names, paths, detection, logs).")
    }
    # installer file(s) + MST + ProductCode swaps - stated only when the NEW name is actually in the script
    $swaps = New-Object System.Collections.Generic.List[object]
    $predSeq = @($Model.InstallSeq); $newInst = @($NewPkg.Installers)
    if (@($newInst).Count -gt 1 -and $predSeq.Count -eq $newInst.Count) {
        for ($i = 0; $i -lt $predSeq.Count; $i++) {
            $nn = "$(if ($newInst[$i].MsiFileName) { $newInst[$i].MsiFileName } elseif ($newInst[$i].ExeFileName) { $newInst[$i].ExeFileName } else { '' })"
            if ("$($predSeq[$i].Name)".Trim() -and $nn) { $swaps.Add(@{ Old = "$($predSeq[$i].Name)"; New = $nn }) }
        }
    } else {
        if ($Model.Installer.MsiFileName -and $NewPkg.MsiFileName) { $swaps.Add(@{ Old = "$($Model.Installer.MsiFileName)"; New = "$($NewPkg.MsiFileName)" }) }
        if ($Model.Installer.ExeFileName -and $NewPkg.ExeFileName) { $swaps.Add(@{ Old = "$($Model.Installer.ExeFileName)"; New = "$($NewPkg.ExeFileName)" }) }
    }
    foreach ($sw in $swaps) {
        if ($sw.Old -eq $sw.New) { continue }
        if (& $has $sw.New) { $done.Add("Installer file swapped: '$($sw.Old)' -> '$($sw.New)'.") }
        if ($mainInstall -and ($mainInstall.IndexOf($sw.Old, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
            $check.Add("The OLD installer name '$($sw.Old)' still appears in the install step - the swap to '$($sw.New)' did not fully take. Check the install command points at your new file.")
        }
    }
    # MST
    if ($Model.Installer.MsiFileName -and $NewPkg.MsiFileName) {
        $newMst = [IO.Path]::GetFileNameWithoutExtension($NewPkg.MsiFileName) + '.mst'
        if (& $has $newMst) { $done.Add("Transform (MST) name updated to '$newMst'.") }
    }
    # ProductCode (detection + uninstall)
    $predPC = Get-PredecessorUninstallPC -Model $Model; if (-not $predPC) { $predPC = "$($Model.Installer.ProductCode)" }
    if ($NewPkg.ProductCode -and (& $has $NewPkg.ProductCode) -and ($predPC -ne "$($NewPkg.ProductCode)")) {
        $done.Add("MSI ProductCode updated to the new build's code $($NewPkg.ProductCode) (used by detection and uninstall).")
    }
    # carried session settings
    if ($Model.Session -and $Model.Session.Count) {
        $nice = @{ ProcToClose='close these apps before install'; ProcToCloseNonUI='close these background apps'; ProcToBlock='block these apps during install';
                   FreeSpace='required free space'; FreeSpaceUninst='required free space (uninstall)'; CheckForReboot='reboot check'; AllowDefer='allow deferral'; ShowBalloonTips='balloon tips' }
        $names = @()
        foreach ($k in 'ProcToClose','ProcToCloseNonUI','ProcToBlock','FreeSpace','FreeSpaceUninst','CheckForReboot','AllowDefer') {
            if ($Model.Session.ContainsKey($k)) { $v = "$($Model.Session[$k])".Trim(); if ($v -and $v -ne "''" -and $v -ne '@()') { $names += $nice[$k] } }
        }
        if ($names.Count) { $done.Add("Kept your predecessor's deployment settings: " + ($names -join '; ') + ".") }
    }
    # custom authored code kept
    $codeLabels = @{ CustomVariables='custom variables'; PreInstallCode='pre-install'; MainInstallCode='install'; PostInstallCode='post-install';
                     PreUninstallCode='pre-uninstall'; MainUninstallCode='uninstall'; PostUninstallCode='post-uninstall'; PreRepairCode='pre-repair'; MainRepairCode='repair'; PostRepairCode='post-repair' }
    $kept = @()
    foreach ($k in $codeLabels.Keys) { if ("$($Model.Code.$k)".Trim()) { $kept += $codeLabels[$k] } }
    if ($kept.Count) { $done.Add("Kept your predecessor's own steps in: " + (($kept | Sort-Object) -join ', ') + ".") }
    # uninstall-previous
    if ($AddUninstallPrevious) {
        $done.Add("Added an 'uninstall the previous version' step so the new package cleanly replaces v$predVer (and any older block the predecessor already carried).")
    } else {
        $done.Add("Skipped the 'uninstall previous version' step (you turned it off) - the new package installs over the old one without removing it first.")
    }
    if ($ScriptText -match 'moved from the variables block') {
        $done.Add("Fixed PSADT v4 scope: moved variables that read the live session out of the variables block into the install/uninstall steps (they would be empty otherwise).")
    }
    # snapshot-assisted reuse: things the NEW version's snapshot added on top of the predecessor (tagged in the script).
    $snapAdds = ([regex]::Matches($ScriptText, '(?im)#\s*\[snapshot-added\]')).Count
    if ($snapAdds -gt 0) {
        $done.Add("Snapshot-assisted: merged $snapAdds new-version cleanup line$(if($snapAdds -ne 1){'s'}) the predecessor didn't already have (each tagged '# [snapshot-added]'; duplicates were skipped).")
    }
    if ($ScriptText -match '#\s*\[snapshot-detection\]') {
        $done.Add("Snapshot-assisted: refreshed the detection key (SoftIdent) from the new version's snapshot (tagged '# [snapshot-detection]').")
    }

    # ---- CHECK (needs a human) ---------------------------------------------------------------------------------
    foreach ($f in @(Get-ScriptReviewFindings -ScriptText $ScriptText -IsPredecessor $true -NewProductCode "$($NewPkg.ProductCode)")) { if ("$f".Trim()) { $check.Add("$f") } }
    if ("$MismatchText".Trim()) { $check.Add("$MismatchText") }
    if ($snapAdds -gt 0) { $check.Add("Review the $snapAdds '# [snapshot-added]' cleanup line$(if($snapAdds -ne 1){'s'}) - they came from THIS version's snapshot, not the predecessor; confirm each removal is wanted.") }
    if ($ScriptText -match '#\s*\[snapshot-detection\]') { $check.Add("The detection key was refreshed from the snapshot ('# [snapshot-detection]') - confirm it detects the new version (the predecessor's was empty or a single ProductCode).") }
    # If the predecessor's OLD ProductCode still appears in a CURRENT-package section (post-install / custom variables),
    # it is likely meant to be the NEW code (e.g. a post-install registry write under the uninstall key). We do NOT
    # auto-swap it (the same call can legitimately remove the OLD version), so flag it for a quick look.
    if ($predPC -and $NewPkg.ProductCode -and ($predPC -ne "$($NewPkg.ProductCode)")) {
        foreach ($sec in @('POST-INSTALLATION', 'CUSTOM APPLICATION VARIABLES')) {
            $segTxt = ([regex]::Match($ScriptText, "(?is)$sec BEGIN(.*?)$sec END")).Groups[1].Value
            if ($segTxt -and ($segTxt.IndexOf($predPC, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                $check.Add("The predecessor's ProductCode $predPC still appears in the $sec section - confirm it should be the new code $($NewPkg.ProductCode) (e.g. a registry write under the uninstall key), or that it is intentionally removing the OLD version.")
                break
            }
        }
    }
    # SoftIdent carried from the predecessor and NOT retargeted (the new ProductCode / real registry DisplayVersion
    # is unknown until the new version is installed) -> always flag for review so it is never shipped stale silently.
    $siLine = ([regex]::Match($ScriptText, "(?im)^[ \t]*[^\r\n'`"]*SoftIdent[ \t]*=[ \t]*['`"]([^'`"]+)['`"]")).Groups[1].Value
    if ($siLine -and $siLine -match '\{[0-9A-Fa-f-]{36}\}') {
        if (-not "$($NewPkg.ProductCode)".Trim()) {
            $check.Add("SoftIdent detection still carries the PREDECESSOR's ProductCode/DisplayVersion (the new values are unknown without installing this EXE). After the test install, check the real uninstall key and correct the ProductCode/name/version in SoftIdent (or run the snapshot, which refreshes it automatically).")
        } elseif ($predPC -and $siLine.IndexOf($predPC, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $check.Add("SoftIdent still contains the predecessor ProductCode $predPC - the swap to $($NewPkg.ProductCode) did not take; update the detection key manually.")
        } else {
            $check.Add("SoftIdent was retargeted to the new installer's ProductCode - after the test install verify the ProductCode, product NAME and DisplayVersion in SoftIdent match the real uninstall registry entry exactly.")
        }
    }

    return @{ Done = $done.ToArray(); Check = $check.ToArray() }
}

# Plain-text rendering of the reuse report - for the in-app dialog and the log.
function Format-PredecessorReportText {
    param([hashtable]$Report, [hashtable]$Model, [hashtable]$NewPkg)
    $done = @($Report.Done); $check = @($Report.Check)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('PREDECESSOR REUSE REPORT')
    [void]$sb.AppendLine(("Reused : {0}" -f "$($Model.Identity.FullName)"))
    [void]$sb.AppendLine(("New    : {0}" -f "$(if($NewPkg.FullName){$NewPkg.FullName}else{"$($NewPkg.Vendor)_$($NewPkg.AppName) v$($NewPkg.Version)"})"))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("DONE AUTOMATICALLY ($($done.Count)) - you can rely on these:")
    if ($done.Count) { foreach ($d in $done) { [void]$sb.AppendLine("  [OK]  $d") } } else { [void]$sb.AppendLine('  (nothing)') }
    [void]$sb.AppendLine('')
    if ($check.Count) {
        [void]$sb.AppendLine("PLEASE CHECK / FILL ($($check.Count)) - only these need you:")
        $i = 0; foreach ($c in $check) { $i++; [void]$sb.AppendLine("  $i.  $c") }
    } else {
        [void]$sb.AppendLine('PLEASE CHECK / FILL (0) - nothing outstanding. Skim the script in the editor, then build.')
    }
    return $sb.ToString().TrimEnd()
}

# Presentable standalone HTML rendering - so the engineer can SAVE the reuse report alongside the package as evidence
# of what the automation did and what was checked (easy for a reviewer / a layman to read).
function Format-PredecessorReportHtml {
    param([hashtable]$Report, [hashtable]$Model, [hashtable]$NewPkg)
    $esc = { param($t) "$t" -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }
    $done = @($Report.Done); $check = @($Report.Check)
    $newName = "$(if($NewPkg.FullName){$NewPkg.FullName}else{"$($NewPkg.Vendor)_$($NewPkg.AppName) v$($NewPkg.Version)"})"
    $doneLi  = if ($done.Count)  { (($done  | ForEach-Object { "<li>$(& $esc $_)</li>" }) -join '') } else { "<li class='muted'>nothing</li>" }
    $checkLi = if ($check.Count) { (($check | ForEach-Object { "<li>$(& $esc $_)</li>" }) -join '') } else { "<li class='ok'>Nothing outstanding - skim the script and build.</li>" }
    $checkColor = if ($check.Count) { '#E0BE7C' } else { '#6A9955' }
    @"
<html><head><meta charset='utf-8'><title>Predecessor reuse report - $(& $esc $newName)</title></head>
<body style='background:#181A1F;color:#E7E9ED;font-family:Segoe UI,Arial;max-width:900px;margin:24px auto;padding:0 16px'>
<h2 style='margin-bottom:4px'>Predecessor reuse report</h2>
<p style='color:#9aa4b2;margin-top:0'>Reused <b>$(& $esc "$($Model.Identity.FullName)")</b> &rarr; New <b>$(& $esc $newName)</b><br>$(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
<h3 style='color:#6A9955'>&#10003; Done automatically ($($done.Count)) <span style='font-weight:normal;color:#9aa4b2;font-size:13px'>- you can rely on these</span></h3>
<ul style='line-height:1.6'>$doneLi</ul>
<h3 style='color:$checkColor'>&#9888; Please check / fill ($($check.Count)) <span style='font-weight:normal;color:#9aa4b2;font-size:13px'>- only these need you</span></h3>
<ul style='line-height:1.6'>$checkLi</ul>
<style>.muted{color:#6b7280}.ok{color:#6A9955}li{margin-bottom:6px}</style>
</body></html>
"@
}
# PSADT v4 variable-scope auto-fix. The CUSTOM VARIABLES block runs BEFORE Import-Module / Open-ADTSession,
# so any line there that reads an ADT-provided value is EMPTY: $adtSession.DeploymentType / DirFiles /
# DirSupportFiles ..., every ADT $env* var ($envProgramData, $envSystem32Directory, ...), and $config* vars.
# (The literal identity fields - AppName/AppVersion/AppVendor/AppArch/AppLang - ARE set, so they stay.)
# Move-V4RuntimeVars relocates the offending assignment lines (and anything that depends on them) into each
# action's PRE-section (Install/Uninstall/Repair), where the session + env are live. Returns @{ Text; Moved }.
$script:V4RuntimeUnsafeRe = @(
    '\$env[A-Z]\w+'                                                                                   # ADT env vars (NOT $env: OS vars)
    '\$config[A-Z]\w+'                                                                                # ADT config vars
    '\$adtSession\.(DeploymentType|DeploymentTypeName|DirFiles|DirSupportFiles|DirAppDeployTemp|InstallPhase|DefaultMsiFile|DefaultMstFile|CurrentDate|CurrentTime|CurrentDateTime)\b'
) -join '|'
function Move-V4RuntimeVars {
    param([string]$ScriptText)
    $result = @{ Text = $ScriptText; Moved = @() }
    if (-not $ScriptText) { return $result }
    $bm = [regex]::Match($ScriptText, '(?m)^.*CUSTOM APPLICATION VARIABLES BEGIN.*$')
    $em = [regex]::Match($ScriptText, '(?m)^.*CUSTOM APPLICATION VARIABLES END.*$')
    if (-not $bm.Success -or -not $em.Success -or $em.Index -le ($bm.Index + $bm.Length)) { return $result }
    $bodyStart = $bm.Index + $bm.Length
    $body = $ScriptText.Substring($bodyStart, $em.Index - $bodyStart)
    $lines = [regex]::Split($body, '\r\n|\r|\n')
    $movedVars = New-Object 'System.Collections.Generic.HashSet[string]'
    $keep = New-Object System.Collections.Generic.List[string]
    $move = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $lines) {
        $assign = [regex]::Match($ln, '^\s*(?:\[[^\]]+\]\s*)?\$(\w+)\s*=')
        # skip lines that OPEN a multi-line construct (here-string / unclosed brace) - too risky to relocate.
        $multiline = ($ln -match '@[''"]\s*$') -or ((([regex]::Matches($ln,'\{')).Count) -ne (([regex]::Matches($ln,'\}')).Count))
        $refUnsafe = ($ln -match $script:V4RuntimeUnsafeRe)
        $refMoved  = $false
        foreach ($mv in $movedVars) { if ($ln -match ('\$' + [regex]::Escape($mv) + '\b')) { $refMoved = $true; break } }
        if ($assign.Success -and -not $multiline -and ($refUnsafe -or $refMoved)) {
            [void]$movedVars.Add($assign.Groups[1].Value); $move.Add($ln.Trim())
        } else { $keep.Add($ln) }
    }
    if ($move.Count -eq 0) { return $result }
    $newBody = ($keep -join "`r`n")
    # SAFETY: if anything we're KEEPING still references a variable we'd move (e.g. a helper FUNCTION defined in
    # the variables block, or a non-assignment statement, uses it), moving the definition into the action scope
    # would break that reference at runtime. Don't move in that case - leave it for the manual-review finding,
    # rather than ship a parse-clean-but-broken script.
    foreach ($mv in $movedVars) { if ($newBody -match ('\$' + [regex]::Escape($mv) + '\b')) { return $result } }
    $block = "`r`n        # [Package Builder] moved from the variables block - these read the live session (DeploymentType / ADT `$env*), which is empty in CUSTOM VARIABLES on v4.`r`n        " +
             ($move -join "`r`n        ") + "`r`n"
    $out = $ScriptText.Substring(0, $bodyStart) + $newBody + $ScriptText.Substring($em.Index)
    foreach ($sec in 'PRE-INSTALLATION BEGIN','PRE-UNINSTALLATION BEGIN','PRE-REPAIR BEGIN') {
        $out = [regex]::Replace($out, "(?m)^(.*$([regex]::Escape($sec)).*)$", { param($mm) $mm.Groups[1].Value + $block })
    }
    $result.Text = $out; $result.Moved = $move.ToArray()
    return $result
}
# Convert a RAW uninstall command (captured from a snapshot's Add/Remove entry) into a PSADT v4 line:
#   MsiExec.exe /X{GUID} /qn        -> Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '{GUID}'
#   "C:\..\unins000.exe" /SILENT    -> Start-ADTProcess -FilePath 'C:\..\unins000.exe' -ArgumentList "/SILENT" ...
# The EXE path is capture-machine-derived (usually the same install dir on the target), so it's flagged for review.
function Convert-RawUninstallToPsadt {
    param([string]$Cmd)
    $c = "$Cmd".Trim(); if (-not $c) { return $null }
    # MULTI: the snapshot can capture SEVERAL applicable uninstall entries (a suite / app+components), one per line.
    # Convert EACH line to a v4 command and emit them all (the caller already ordered them, uninstall-reverse).
    if ($c -match '[\r\n]') {
        $lines = @($c -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($lines.Count -gt 1) {
            return (@($lines | ForEach-Object { Convert-RawUninstallToPsadt -Cmd $_ }) -join "`r`n")
        }
        $c = $lines[0]
    }
    $g = [regex]::Match($c, '(?i)\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}')
    if ($c -match '(?i)msiexec' -and $g.Success) {
        return "Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '$($g.Value)'"
    }
    if ($c -match '^\s*"([^"]+)"\s*(.*)$') { $path = $Matches[1]; $uargs = $Matches[2].Trim() }
    elseif ($c -match '^\s*(\S+)\s*(.*)$') { $path = $Matches[1]; $uargs = $Matches[2].Trim() }
    else { $path = $c; $uargs = '' }
    $line = if ($uargs) { "Start-ADTProcess -FilePath '$path' -ArgumentList `"$($uargs -replace '"','`"')`" -WindowStyle 'Hidden'" }
            else        { "Start-ADTProcess -FilePath '$path' -WindowStyle 'Hidden'" }
    return "## REVIEW: this uninstall command was CAPTURED from the snapshot machine - confirm the path is valid on target machines.`r`n$line"
}
function Get-ExeCommandSet {
    param([string]$Exe, [string]$InstallParams, [string]$UninstallParams, [string]$UninstallCommand)
    # ArgumentList is emitted in DOUBLE quotes (team convention). Any double-quote INSIDE the args is escaped with
    # a backtick (`") so PowerShell treats it as a literal quote, not a string terminator (e.g. /v"qn" -> "/v`"qn`"").
    $eaI = ("$InstallParams"   -replace '"', '`"')
    $eaU = ("$UninstallParams" -replace '"', '`"')
    # Clear, actionable REVIEW markers (not a bare "# TODO") so the tool can surface them to the user and
    # the packager knows exactly what to fill in. Get-ReviewItems scans for "## REVIEW:" lines.
    $install = "Start-ADTProcess -FilePath `"`$(`$adtSession.DirFiles)\$Exe`" -ArgumentList `"$eaI`" -WindowStyle 'Hidden'"
    if (-not $InstallParams) {
        $install = "## REVIEW: no SILENT INSTALL switches were given for '$Exe'. Add them below (e.g. /S, /VERYSILENT, /qn) or the installer may show its GUI / fail to install silently.`r`n$install"
    }
    # Uninstall priority: a CAPTURED full command (from snapshot) -> the installer EXE + uninstall args -> review TODO.
    $uninstall = if ("$UninstallCommand".Trim()) {
        Convert-RawUninstallToPsadt -Cmd $UninstallCommand
    } elseif ($UninstallParams) {
        "Start-ADTProcess -FilePath `"`$(`$adtSession.DirFiles)\$Exe`" -ArgumentList `"$eaU`" -WindowStyle 'Hidden'"
    } else { "## REVIEW: no UNINSTALL command for '$Exe'. Add the uninstaller path + silent switches here, or this package cannot uninstall cleanly." }
    # EXE convention: Repair = re-install; Pre-Repair = uninstall first.
    return @{ MainInstall = $install; MainUninstall = $uninstall; MainRepair = $install; PreRepair = $uninstall }
}
function Get-LooseFilesCommandSet {
    param([string]$InstallPath, [string]$ZipName, [array]$Shortcuts, [bool]$CreateArp, [string]$AppName)
    $p   = "$InstallPath".TrimEnd('\')
    $zip = if ($ZipName) { $ZipName } else { 'Payload' }
    if ($zip -notmatch '(?i)\.zip$') { $zip = "$zip.zip" }
    $ins = New-Object System.Collections.Generic.List[string]
    $un  = New-Object System.Collections.Generic.List[string]
    # Loose payload is extracted at install from Files\. F25/F34: GPF's Extensions module defines Expand-ZipFile (NO 'MTB'
    # prefix, same -Path/-Destination/-Override signature); MTB uses Expand-MTBZipFile. Brand-gated so neither template is
    # crossed. $Destination is the caller-chosen path (GPF: $envTemp\<AppName>_<Version> - a temp staging dir).
    $expandFn = if ((Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') { 'Expand-ZipFile' } else { 'Expand-MTBZipFile' }
    $ins.Add("$expandFn -Path `"`$(`$adtSession.DirFiles)\$zip`" -Destination `"$p`" -Override")
    # Start Menu shortcut(s) - one per chosen target exe (icon taken from the exe itself).
    foreach ($sc in @($Shortcuts)) {
        if (-not $sc) { continue }
        $tgtRel = "$($sc.Target)".TrimStart('\')
        $name   = if ($sc.Name) { $sc.Name } else { [IO.Path]::GetFileNameWithoutExtension($tgtRel) }
        $tgt    = "$p\$tgtRel"
        $ins.Add("New-ADTShortcut -Path `"`$envCommonStartMenuPrograms\$name.lnk`" -TargetPath `"$tgt`" -IconLocation `"$tgt`"")
        $un.Add("Remove-ADTFile -Path `"`$envCommonStartMenuPrograms\$name.lnk`"")
    }
    # ARP / Application Wizard entry (PSADT extension; icon read from SupportFiles\Icon.ico). GPF's Extensions module
    # defines Set-/Remove-ApplicationWizardEntry (NO 'MTB' prefix); MTB uses Set-/Remove-MTBApplicationWizardEntry.
    if ($CreateArp) {
        $awPrefix = if ((Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') { '' } else { 'MTB' }
        $appArg = if ($AppName) { " -ApplicationName '$AppName'" } else { '' }
        $ins.Add("Set-${awPrefix}ApplicationWizardEntry$appArg")
        $un.Add("Remove-${awPrefix}ApplicationWizardEntry")
    }
    $un.Add("Remove-ADTFolder -Path `"$p`"")
    $install = ($ins -join "`r`n"); $uninstall = ($un -join "`r`n")
    # Repair = re-extract (full install); Pre-Repair = the full uninstall (removes shortcut(s) + ARP
    # + folder before the reinstall). Only branding key / reboot are kept out of Pre-Repair.
    return @{ MainInstall = $install; MainUninstall = $uninstall; MainRepair = $install; PreRepair = $uninstall }
}

# ZIP PAYLOAD command set (GPF): the source is a single .zip kept VERBATIM in Files\; at install we Expand-ZipFile it to
# $envTemp\<App>_<Version> and RUN the installer(s) the packager selected from inside it (their path is inside the zip).
# .msi -> Start-ADTMsiProcess; .exe -> Start-ADTProcess (+ a review to fill the silent switches); .bat/.cmd -> cmd /c;
# .ps1 -> powershell -ExecutionPolicy Bypass -File. Uninstall/repair are review-stubbed (the packager knows the app's
# uninstall). GPF uses Expand-ZipFile (no MTB); the zip name + extract dir come from the caller.
function Get-ZipPayloadCommandSet {
    param([string]$ZipName, [string]$ExtractDir, [object[]]$RunItems)
    $expandFn = if ((Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') { 'Expand-ZipFile' } else { 'Expand-MTBZipFile' }
    $ins = New-Object System.Collections.Generic.List[string]
    $ins.Add("$expandFn -Path `"`$(`$adtSession.DirFiles)\$ZipName`" -Destination `"$ExtractDir`" -Override")
    foreach ($it in @($RunItems)) {
        $rel = "$($it.RelPath)".TrimStart('\'); if (-not $rel) { continue }
        $p   = "$ExtractDir\$rel"
        switch -Regex ("$($it.Extension)".ToLower()) {
            '\.msi$' { $ins.Add("Start-ADTMsiProcess -Action 'Install' -FilePath `"$p`"") }
            '\.exe$' { $ins.Add("## REVIEW: set the silent install switches for $($it.Name) (from the vendor's install instructions).") ; $ins.Add("Start-ADTProcess -FilePath `"$p`" -ArgumentList '/S'") }
            '\.(bat|cmd)$' { $ins.Add("Start-ADTProcess -FilePath `"`$envWinDir\System32\cmd.exe`" -ArgumentList '/c', `"$p`"") }
            '\.ps1$' { $ins.Add("Start-ADTProcess -FilePath 'powershell.exe' -ArgumentList '-ExecutionPolicy', 'Bypass', '-File', `"$p`"") }
            default  { $ins.Add("Start-ADTProcess -FilePath `"$p`"") }
        }
    }
    $install = ($ins -join "`r`n")
    $un = "## REVIEW: add the uninstall for this payload (e.g. run its uninstaller / MsiExec /X, or Remove-ADTFolder for a copy-only payload)."
    return @{ MainInstall = $install; MainUninstall = $un; MainRepair = $install; PreRepair = '' }
}

function Get-MultiCommandSet {
    param([array]$Order)
    # PREREQUISITE auto-chaining: a recognised runtime (vc_redist, .NET, WebView2, DirectX) MUST install BEFORE the app.
    # Stable-sort recognised prerequisites to the FRONT (keeping the engineer's relative order otherwise); uninstall is
    # then the exact reverse (app first, prereq last) - correct. A prereq EXE with no switches gets its standard silent
    # switches. We add a header comment naming what installs first, so the reorder is visible in the editor.
    $nameOf  = { param($it) "$(if ($it.MsiFileName) { $it.MsiFileName } elseif ($it.ExeFileName) { $it.ExeFileName } else { '' })" }
    $isPre   = { param($it) if (Get-Command Get-PrerequisiteSpec -ErrorAction SilentlyContinue) { [bool](Get-PrerequisiteSpec -Name (& $nameOf $it)).IsPrereq } else { $false } }
    $pre     = @($Order | Where-Object { & $isPre $_ })
    $rest    = @($Order | Where-Object { -not (& $isPre $_) })
    $ordered = @($pre + $rest)
    $oneOf = {
        param($it)
        if ("$($it.Type)" -eq 'MSI') { Get-MsiCommandSet -Msi $it.MsiFileName -Mst $it.MstFileName -ProductCode $it.ProductCode -NoMst:([bool]$it.NoMst) }
        else {
            $ip = "$($it.InstallParams)"
            if (-not $ip.Trim() -and (Get-Command Get-PrerequisiteSpec -ErrorAction SilentlyContinue)) {
                $sp = Get-PrerequisiteSpec -Name "$($it.ExeFileName)"; if ($sp.IsPrereq) { $ip = $sp.Install }
            }
            Get-ExeCommandSet -Exe $it.ExeFileName -InstallParams $ip -UninstallParams $it.UninstallParams
        }
    }
    $inst = @(); $un = @()
    foreach ($it in $ordered)                     { $inst += (& $oneOf $it).MainInstall }
    for ($i = $ordered.Count - 1; $i -ge 0; $i--) { $un += (& $oneOf $ordered[$i]).MainUninstall }   # uninstall in reverse
    $head = if (@($pre).Count) { "## Prerequisite(s) install first: $((@($pre | ForEach-Object { & $nameOf $_ })) -join ', ')`r`n" } else { '' }
    # Repair of a multi-installer package = uninstall everything (reverse) then install again.
    return @{ MainInstall = ($head + ($inst -join "`r`n")); MainUninstall = ($un -join "`r`n"); MainRepair = ($head + ($inst -join "`r`n")); PreRepair = ($un -join "`r`n") }
}
# Pick a command set from NewPkg. Mode is taken from NewPkg.InstallerMode when set,
# else inferred (Multiple > SingleMSI > SingleEXE > None).
function New-StandardCommands {
    param([hashtable]$NewPkg)
    $mode = "$($NewPkg.InstallerMode)"
    if (-not $mode) {
        if     (@($NewPkg.Installers).Count -gt 1) { $mode = 'Multiple' }
        elseif ($NewPkg.MsiFileName)               { $mode = 'SingleMSI' }
        elseif ($NewPkg.ExeFileName)               { $mode = 'SingleEXE' }
        else                                       { $mode = 'None' }
    }
    $cmds = switch ($mode) {
        'ZipPayload' {
            # GPF: source kept as one verbatim .zip; Expand-ZipFile to $envTemp\<App>_<Ver> at install, then run the
            # packager-selected installer(s) from inside it.
            $ed = "`$envTemp\$($NewPkg.AppName)_$($NewPkg.Version)"
            Get-ZipPayloadCommandSet -ZipName "$($NewPkg.ZipName)" -ExtractDir $ed -RunItems @($NewPkg.ZipRunItems)
        }
        'SingleMSI'  { Get-MsiCommandSet -Msi $NewPkg.MsiFileName -Mst $NewPkg.MstFileName -ProductCode $NewPkg.ProductCode -NoMst:([bool]$NewPkg.NoMst) }
        'SingleEXE'  { Get-ExeCommandSet -Exe $NewPkg.ExeFileName -InstallParams $NewPkg.InstallParams -UninstallParams $NewPkg.UninstallParams -UninstallCommand "$($NewPkg.UninstallCommand)" }
        'LooseFiles' {
            $pf   = if ("$($NewPkg.Arch)" -match '(?i)x86') { '$envProgramFilesX86' } else { '$envProgramFiles' }
            # F25/F34: GPF extracts the source zip to a TEMP staging dir ($envTemp\<AppName>_<Version> = C:\Windows\Temp\...
            # under SYSTEM) rather than straight into Program Files - the team's convention for zipped sources. MTB keeps
            # the Program Files layout.
            $isGpf = (Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF'
            $path = if ($NewPkg.InstallPath) { $NewPkg.InstallPath }
                    elseif ($isGpf) { "`$envTemp\$($NewPkg.AppName)_$($NewPkg.Version)" }
                    else { "$pf\$($NewPkg.Vendor)\$($NewPkg.AppName)" }
            $zip  = if ($NewPkg.ZipName) { $NewPkg.ZipName } elseif ($NewPkg.FullName) { $NewPkg.FullName } else { $NewPkg.AppName }
            Get-LooseFilesCommandSet -InstallPath $path -ZipName "$zip" -Shortcuts @($NewPkg.Shortcuts) -CreateArp ([bool]$NewPkg.CreateArp) -AppName "$($NewPkg.AppName)"
        }
        'Multiple'   { Get-MultiCommandSet -Order @($NewPkg.Installers) }
        default      { @{ MainInstall = ''; MainUninstall = ''; MainRepair = ''; PreRepair = '' } }
    }
    # Custom actions + snapshot cleanups are injected into PRE-INSTALL / POST-INSTALL / PRE-UNINSTALL so the
    # package actually performs them (the packager's own steps: close apps, copy a config, registry tweaks, plus
    # the snapshot exclusions in POST-INSTALL).
    if ("$($NewPkg.PreInstallExtra)".Trim())     { $cmds.PreInstall    = "$($NewPkg.PreInstallExtra)" }
    if ("$($NewPkg.PostInstallExtra)".Trim())    { $cmds.PostInstall   = "$($NewPkg.PostInstallExtra)" }
    if ("$($NewPkg.PreUninstallExtra)".Trim())   { $cmds.PreUninstall  = "$($NewPkg.PreUninstallExtra)" }
    # POST-UNINSTALL extras (cert/driver cleanup) are INSERTED into the POST-UNINSTALLATION section after its
    # "<Perform ... tasks here>" marker - Set-SectionBody preserves the template's branding removal that follows.
    if ("$($NewPkg.PostUninstallExtra)".Trim())  { $cmds.PostUninstall = "$($NewPkg.PostUninstallExtra)" }
    return $cmds
}
# Inject a command set into the template's MAIN-INSTALL / MAIN-UNINSTALL / MAIN-REPAIR /
# PRE-REPAIR sections (only where the command is non-empty).
function Add-StandardCommands {
    param([string]$Template, [hashtable]$Cmds)
    $byField = @{}
    foreach ($s in $script:SectionMarkers) { $byField[$s.F] = $s }
    foreach ($pair in @(@('MainInstallCode', $Cmds.MainInstall), @('MainUninstallCode', $Cmds.MainUninstall),
                        @('MainRepairCode', $Cmds.MainRepair),   @('PreRepairCode', $Cmds.PreRepair),
                        @('PreInstallCode', $Cmds.PreInstall),   @('PostInstallCode', $Cmds.PostInstall),
                        @('PreUninstallCode', $Cmds.PreUninstall), @('PostUninstallCode', $Cmds.PostUninstall))) {
        $sec = $byField[$pair[0]]
        if ($sec -and $pair[1]) { $Template = Set-SectionBody -Template $Template -Begin $sec.B -End $sec.E -Body $pair[1] -Pre $sec.Pre }
    }
    return $Template
}

# ProcToBlock should mirror ProcToClose by default - the same apps you CLOSE before install you also BLOCK during it.
# Used by BOTH the fresh and predecessor-reuse builds, idempotently:
#   REPLACE ProcToBlock with ProcToClose's value when ProcToBlock has NO real process names yet - i.e. it is empty
#     (@() / '' / ""), a REFERENCE to ProcToClose ($adtSession.ProcToClose / $VWG_ProcToClose / $ProcToClose), or a
#     <placeholder>. (These are template/leftover forms, not an authored list.)
#   SKIP (leave untouched) when ProcToBlock ALREADY lists real, quoted process names - never clobber an authored list.
# "Has a real process" = contains a quoted, NON-empty literal ('firefox' / "chrome"); a reference or @() has none.
function Set-ProcToBlockDefault {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $hasReal = { param($v) [bool]([regex]::IsMatch("$v", "'[^']+'|`"[^`"]+`"")) }
    # GPF: field lines carry the wrapper prefix ("[string[]] $Global:VWG_ProcToClose = ...") - match BOTH shapes.
    $pcm = [regex]::Match($Text, "(?im)$(Get-FieldLinePrefix 'ProcToClose')(.+?)[ \t]*$")
    if (-not $pcm.Success) { return $Text }
    $pcVal = $pcm.Groups[2].Value.Trim()
    # guard against a multi-line / unbalanced array literal (capture is single-line) - don't risk corrupting it
    if (([regex]::Matches($pcVal, '\(')).Count -ne ([regex]::Matches($pcVal, '\)')).Count) { return $Text }
    if (-not (& $hasReal $pcVal)) { return $Text }     # ProcToClose has nothing real to mirror
    $pbm = [regex]::Match($Text, "(?im)$(Get-FieldLinePrefix 'ProcToBlock')(.+?)[ \t]*$")
    if (-not $pbm.Success) { return $Text }
    if (& $hasReal $pbm.Groups[2].Value.Trim()) { return $Text }   # ProcToBlock already authored -> SKIP
    $Text = $Text.Substring(0, $pbm.Index) + $pbm.Groups[1].Value + $pcVal + $Text.Substring($pbm.Index + $pbm.Length)
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "ProcToBlock defaulted to ProcToClose ($pcVal)." }
    return $Text
}

# F52: carry the INSTALLATION PROGRESS BAR from the predecessor. The template ships it COMMENTED
# (#Show-ADTInstallationProgress) inside each section's "If ($VWG_UseDialogs){ }" block; a predecessor that
# ENABLED it has the call uncommented. When the predecessor had it active in a section (Install/Uninstall/Repair),
# uncomment the SAME section's template line so the current package keeps the behaviour. Section-scoped via the
# MAIN-* BEGIN/END markers so enabling install never touches uninstall/repair. Returns the number of sections
# enabled (>0 -> a review item is raised: app behaviour varies version to version, so the packager must verify).
function Set-PredecessorProgressBar {
    param([string]$Text, [hashtable]$Model)
    if (-not $Text -or -not $Model) { return @{ Text = $Text; Enabled = 0 } }
    $pred = "$($Model.RawV4Content)"
    if (-not $pred) { return @{ Text = $Text; Enabled = 0 } }
    # An ACTIVE progress call = a Show-(ADT)InstallationProgress line NOT commented out (no leading # before it).
    $activeRx = '(?im)^[ \t]*(?<!#)Show-(?:ADT)?InstallationProgress\b'
    $count = 0
    foreach ($sec in @('INSTALLATION','UNINSTALLATION','REPAIR')) {
        $begin = "MAIN-$sec BEGIN"; $end = "MAIN-$sec END"
        # does the PREDECESSOR have progress active in this section?
        $pm = [regex]::Match($pred, "(?s)$([regex]::Escape($begin))(.*?)$([regex]::Escape($end))")
        if (-not $pm.Success -or -not [regex]::IsMatch($pm.Groups[1].Value, $activeRx)) { continue }
        # uncomment the template line in the SAME section of $Text (only if still commented)
        $tm = [regex]::Match($Text, "(?s)($([regex]::Escape($begin)))(.*?)($([regex]::Escape($end)))")
        if (-not $tm.Success) { continue }
        $body = $tm.Groups[2].Value
        $newBody = [regex]::Replace($body, '(?im)^([ \t]*)#([ \t]*Show-(?:ADT)?InstallationProgress\b[^\r\n]*)', '${1}${2}')
        if ($newBody -ne $body) {
            $Text = $Text.Substring(0, $tm.Groups[2].Index) + $newBody + $Text.Substring($tm.Groups[2].Index + $tm.Groups[2].Length)
            $count++
        }
    }
    if ($count -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) { Write-Log "Installation progress bar enabled in $count section(s) to match the predecessor." }
    return @{ Text = $Text; Enabled = $count }
}

# Pull the most DISTINCTIVE identifier out of a cleanup command line, used to decide whether the predecessor already
# handles that resource. Prefers a -Name/-TaskName/-ValueName value, then a path's leaf (file / shortcut name), then the
# longest quoted literal. Returns '' when nothing usable (caller then keeps the line - safer to add than to wrongly skip).
function Get-CleanupTarget {
    param([string]$Line)
    if (-not $Line) { return '' }
    $nameM = [regex]::Match($Line, "(?i)-(?:Name|TaskName|ValueName)[ \t]+(?:'([^']+)'|`"([^`"]+)`")")
    if ($nameM.Success) { $v = if ($nameM.Groups[1].Value) { $nameM.Groups[1].Value } else { $nameM.Groups[2].Value }; if ($v.Trim().Length -ge 3) { return $v.Trim() } }
    $lits = @([regex]::Matches($Line, "'([^']+)'|`"([^`"]+)`"") | ForEach-Object { if ($_.Groups[1].Value) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
    if (-not $lits.Count) { return '' }
    foreach ($l in $lits) { if ($l -match '(?i)\.(lnk|exe|dll|sys|inf|cat|ttf|otf)(["'']|$)' -or ($l -match '\\' -and $l -match '\.')) { $leaf = ($l -split '[\\/]')[-1]; if ($leaf.Trim().Length -ge 4) { return $leaf.Trim() } } }
    return (($lits | Sort-Object { $_.Length } -Descending | Select-Object -First 1)).Trim()
}

# Append a body just before a section's END marker, keeping ALL existing section content intact (additive only).
function Append-ToSection {
    param([string]$Text, [string]$Begin, [string]$End, [string]$Body)
    if (-not "$Body".Trim()) { return $Text }
    $m = [regex]::Match($Text, "(?s)($Begin)(.*?)($End)")
    if (-not $m.Success) { return $Text }
    $newMid = $m.Groups[2].Value.TrimEnd("`r","`n") + "`r`n`r`n" + ("$Body".Trim("`r","`n")) + "`r`n"
    return $Text.Remove($m.Index, $m.Length).Insert($m.Index, $m.Groups[1].Value + $newMid + $m.Groups[3].Value)
}

# SNAPSHOT-ASSISTED REUSE: use the NEW version's machine-snapshot to refresh/augment a reused predecessor script,
# WITHOUT touching the predecessor's core install/uninstall/repair commands. Only ADDITIVE / value-refresh changes, all
# de-duplicated against what the predecessor already does (the user's rule: "if already similar there then not needed"):
#   FreeSpace  -> RAISED to the new version's measured footprint when bigger (never lowered).
#   SoftIdent  -> refreshed from the new version's detection ($NewPkg.SnapshotSoftIdent, e.g. a wrapped-EXE's real MSI
#                 GUID) ONLY when the predecessor's detection is missing/placeholder or a single ProductCode; a
#                 hand-crafted multi-condition detection is left intact. Tagged '# [snapshot-detection]' when changed.
#   ProcToClose/Block -> UNION in any new-version app exes the predecessor didn't list (never removes any).
#   Cleanups   -> each snapshot cleanup whose target ISN'T already handled is appended to POST-INSTALL/UNINSTALL, tagged
#                 '# [snapshot-added]'. Build-FreshScript already does all of this via New-StandardCommands; this is the
#                 reuse-mode equivalent, kept separate so the predecessor's proven logic is never duplicated or clobbered.
function Merge-SnapshotDeltas {
    param([string]$Text, [hashtable]$NewPkg, [hashtable]$Model)
    if (-not $Text -or -not $NewPkg) { return $Text }
    $log = { param($m) if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Snapshot-reuse: $m" } }

    # FreeSpace: raise to the new version's footprint (max of snapshot-derived vs the predecessor's current value).
    # Read via the field-line prefix so the GPF wrapper line ("[int32] $Global:VWG_FreeSpace = '500'") is SEEN -
    # an MTB-shaped read returned 0 there and the payload floor (150) OVERWROTE the predecessor's real value.
    if ("$($NewPkg.FreeSpace)".Trim() -match '^\d+$') {
        $snap = [int]$NewPkg.FreeSpace
        $cm = [regex]::Match($Text, "(?im)$(Get-FieldLinePrefix 'FreeSpace')'?(\d+)'?")
        $cur = if ($cm.Success) { [int]$cm.Groups[2].Value } else { 0 }
        if ($snap -gt $cur) { $Text = Set-SessionValue -Text $Text -Field 'FreeSpace' -Value "'$snap'"; & $log "FreeSpace raised $cur -> $snap MB (new-version footprint)." }
    }

    # SoftIdent: adopt the new version's detection only when the predecessor's is missing/placeholder/single-GUID.
    $snapSI = "$($NewPkg.SnapshotSoftIdent)".Trim()
    if ($snapSI) {
        $guidRx = '(?i)\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}'
        $snapGuid = [regex]::Match($snapSI, $guidRx).Value
        # match BOTH line shapes (MTB "SoftIdent =" and GPF "[string] $Global:VWG_SoftIdent =")
        $sm = [regex]::Match($Text, "(?im)$(Get-FieldLinePrefix 'SoftIdent')(.+?)\s*$")
        if ($sm.Success) {
            $curRHS = $sm.Groups[2].Value.Trim()
            $curSI  = $curRHS.Trim("'", '"')
            $curGuids = @([regex]::Matches($curSI, $guidRx) | ForEach-Object { $_.Value })
            $already  = $snapGuid -and (@($curGuids) | Where-Object { $_ -ieq $snapGuid })
            # "simple" = safe to replace: empty, a <placeholder>, or a SINGLE plain ProductCode path. A multi-GUID or an
            # EXPRESSION-based detection (a variable, -and/-or, a Test-Path/Get-ItemProperty cmdlet) is hand-crafted by
            # the packager -> leave it intact. The GPF runtime token $($VWG_CurrentRegWOW) and its double quotes are
            # part of their PLAIN house format - ignore them when deciding.
            $curPlain = [regex]::Replace($curSI, '(?i)\$\(\$?VWG_CurrentRegWO?W\)', '')
            $isExpr = $curPlain -match '(?i)(\$|`"|-and\b|-or\b|Test-Path|Get-ItemProperty)'
            $simple = (-not $curSI) -or ($curSI -match '<[^>]*>') -or (@($curGuids).Count -le 1 -and -not $isExpr)
            if ($snapGuid -and -not $already -and $simple) {
                $hardWow = if (Get-Command Test-PBConvertFlag -ErrorAction SilentlyContinue) { Test-PBConvertFlag 'RegWowHardcode' } else { $true }
                if ($hardWow) {
                    $rhs = Format-BrandSoftIdent -Value $snapSI -Arch "$($NewPkg.Arch)"
                    $Text = Set-SessionValue -Text $Text -Field 'SoftIdent' -Value "$rhs  # [snapshot-detection]"
                } else {
                    # GPF: the WRAPPER must stay PLAIN (no token) - writing Format-BrandSoftIdent here put the
                    # $($VWG_CurrentRegWOW) token in the wrapper. Set-GpfSoftIdentTwoPlace (called at the end of the
                    # build) then re-derives the x86-only tokened copy in CUSTOM APPLICATION VARIABLES.
                    $rhs = Format-GpfSoftIdentPlain -Value $snapSI
                    $Text = Set-SessionValue -Text $Text -Field 'SoftIdent' -Value "$rhs  # [snapshot-detection]"
                    if ("$($NewPkg.Arch)" -match '(?i)x86|32') {
                        $Text = Add-GpfCustomVar -Text $Text -Line ('[string]$Global:VWG_SoftIdent   =  ' + (Format-BrandSoftIdent -Value $snapSI -Arch "$($NewPkg.Arch)"))
                    }
                }
                & $log "SoftIdent refreshed to new-version detection $snapGuid."
            }
        }
    }

    # ProcToClose / ProcToBlock: union in new-version app exes not already listed (additive only).
    # GPF: the authoritative close-list is AppProcessesToClose (the VWG_ProcToClose line is a BRIDGE and must never
    # be written); target it when present. Reads are field-line-prefix based so both template shapes are seen.
    $snapProcs = @($NewPkg.SnapshotProcs) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
    if ($snapProcs.Count) {
        $procTargets = if ([regex]::IsMatch($Text, "(?im)$(Get-FieldLinePrefix 'AppProcessesToClose')")) { @('AppProcessesToClose','ProcToBlock') } else { @('ProcToClose','ProcToBlock') }
        foreach ($field in $procTargets) {
            $m = [regex]::Match($Text, "(?im)$(Get-FieldLinePrefix $field)(.+?)[ \t]*$")
            if (-not $m.Success) { continue }
            if ($m.Groups[2].Value.Trim() -match '^\$') { continue }   # RHS is a BRIDGE (e.g. = $adtSession.X / $VWG_ProcToClose) - leave it
            $cur = @([regex]::Matches($m.Groups[2].Value, "'([^']+)'|`"([^`"]+)`"") | ForEach-Object { if ($_.Groups[1].Value) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
            if ($field -eq 'ProcToBlock' -and $cur.Count -eq 0) { continue }   # empty -> Set-ProcToBlockDefault mirrors the full ProcToClose later
            $new = @($snapProcs | Where-Object { $n = $_; -not (@($cur) | Where-Object { $_ -ieq $n }) })
            if ($new.Count) {
                $lit = '@(' + ((@($cur + $new) | Select-Object -Unique | ForEach-Object { "'$_'" }) -join ', ') + ')'
                $Text = Set-SessionValue -Text $Text -Field $field -Value $lit
                if ($field -eq 'ProcToClose') { & $log "ProcToClose gained $($new -join ', ')." }
            }
        }
    }

    # Cleanups: append only the snapshot cleanups the predecessor doesn't already perform (target not in the script).
    foreach ($pair in @(@('PostInstallExtra','POST-INSTALLATION'), @('PostUninstallExtra','POST-UNINSTALLATION'))) {
        $raw = "$($NewPkg.($pair[0]))"
        if (-not $raw.Trim()) { continue }
        $netNew = New-Object System.Collections.Generic.List[string]
        foreach ($line in ($raw -split "`r?`n")) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            $tgt = Get-CleanupTarget -Line $t
            if ($tgt -and ($Text.IndexOf($tgt, [StringComparison]::OrdinalIgnoreCase) -ge 0)) { continue }   # predecessor already handles it
            $netNew.Add($line.TrimEnd() + '  # [snapshot-added]')
        }
        if ($netNew.Count) {
            $mk = $script:SectionMarkers | Where-Object { $_.B -match [regex]::Escape($pair[1]) } | Select-Object -First 1
            if ($mk) { $Text = Append-ToSection -Text $Text -Begin $mk.B -End $mk.E -Body ($netNew -join "`r`n"); & $log "added $($netNew.Count) net-new cleanup(s) to $($pair[1])." }
        }
    }
    return $Text
}

# Fill the blank template's identity from the new package (no predecessor case),
# then inject the standard commands for the chosen installer type.
function Build-FreshScript {
    param([hashtable]$NewPkg, [string]$Template)
    $out = $Template
    foreach ($f in @('AppVendor','Vendor'),@('AppName','AppName'),@('AppArch','Arch'),
                   @('AppLang','Lang'),@('AppRevision','Revision'),@('AppVersion','Version'),
                   @('OrderNumber','Ritm'),@('AppScriptAuthor','Author')) {
        $out = Set-SessionField $out $f[0] "$($NewPkg[$f[1]])"
    }
    $out = Set-SessionField $out 'AppScriptDate'   (Get-Date -Format 'yyyy-MM-dd')
    $out = Set-SessionField $out 'AppScriptAuthor' (Format-AuthorName "$($NewPkg.Author)")
    # GPF: InstallTitle is filled explicitly (their house style; MTB leaves the template default). #13: VW (G1V) shows
    # vendor "Volkswagen" in the title only; and when Vendor==AppName the name is not repeated. Brand-aware helper.
    if ((Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') {
        $out = Set-SessionField $out 'InstallTitle' (Get-GpfInstallTitle -NewPkg $NewPkg -Brand (Get-GpfTargetBrand -NewPkg $NewPkg))
    }
    # Auto-fill required disk space (MB) from the source payload size when provided.
    if ($NewPkg.FreeSpace) { $out = Set-SessionValue -Text $out -Field 'FreeSpace' -Value "'$($NewPkg.FreeSpace)'" }
    if ($NewPkg.SoftIdent) {
        $hardWow = if (Get-Command Test-PBConvertFlag -ErrorAction SilentlyContinue) { Test-PBConvertFlag 'RegWowHardcode' } else { $true }
        if ($hardWow) {
            # MTB: one wrapper SoftIdent, arch hardcoded into the hive (unchanged).
            $out = Set-SessionValue -Text $out -Field 'SoftIdent' -Value (Format-BrandSoftIdent -Value "$($NewPkg.SoftIdent)" -Arch "$($NewPkg.Arch)")
        } else {
            # GPF: the WRAPPER always carries the PLAIN value (single-quoted, no token) - correct for x64 as-is.
            $out = Set-SessionValue -Text $out -Field 'SoftIdent' -Value (Format-GpfSoftIdentPlain -Value "$($NewPkg.SoftIdent)")
            # The $($VWG_CurrentRegWOW) two-place re-assignment in CUSTOM APPLICATION VARIABLES is an x86-ONLY convention
            # (GandalfClient style): WoW6432Node only redirects on 32-bit apps, so the runtime token resolves the hive at
            # deploy time. A 64-bit package NEVER redirects, so it gets the single plain wrapper only (Freia x64 style) -
            # emitting the token there would be wrong syntax for x64.
            if ("$($NewPkg.Arch)" -match '(?i)x86|32') {
                $wowVal = Format-BrandSoftIdent -Value "$($NewPkg.SoftIdent)" -Arch "$($NewPkg.Arch)"
                $out = Add-GpfCustomVar -Text $out -Line ('[string]$Global:VWG_SoftIdent   =  ' + $wowVal)
            }
        }
    }
    # Auto ProcToClose/ProcToBlock from the app's OWN executables (the Start-Menu shortcut targets the snapshot found)
    # so Show-ADTInstallationWelcome closes/blocks the right processes. Written as a PowerShell array literal.
    foreach ($pf in @('ProcToClose','ProcToBlock')) {
        $names = @($NewPkg[$pf]) | Where-Object { "$_".Trim() } | Select-Object -Unique
        if (@($names).Count) {
            $lit = '@(' + ((@($names) | ForEach-Object { "'" + ("$_" -replace "'","''") + "'" }) -join ', ') + ')'
            $out = Set-SessionValue -Text $out -Field $pf -Value $lit
        }
    }
    # SoftIdent hive matches the package's bitness (x86 -> WoW6432Node, x64 -> not). Also resolve the blank
    # template's <Appname>/<version> placeholders to the real identity, so a FRESH build never ships a literal
    # '<Appname> [DisplayVersion = <version>]' detection key. (Predecessor reuse fills SoftIdent from the
    # predecessor's own value, so this placeholder only ever survived on the fresh path.)
    $out = [regex]::Replace($out, "(?m)(^[ \t]*SoftIdent[ \t]*=[ \t]*')([^']*)(')", {
        param($m)
        $val = $m.Groups[2].Value
        $val = $val -replace '(?i)<Appname>', ([string]$NewPkg.AppName).Replace('$','$$')
        $val = $val -replace '(?i)<version>', ([string]$NewPkg.Version).Replace('$','$$')
        $m.Groups[1].Value + (Normalize-SoftIdent -Value $val -Arch "$($NewPkg.Arch)") + $m.Groups[3].Value
    })
    # GPF: upgrade the Main-section "<Action> of ..." scaffold log to "... is successful." BEFORE inserting the command,
    # so the command lands BETWEEN the Start/success logs (gold layout) instead of after both (which looked duplicated).
    if ((Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') { $out = Set-GpfMainSuccessLog -Text $out }
    $out = Add-StandardCommands -Template $out -Cmds (New-StandardCommands -NewPkg $NewPkg)
    $out = Set-TemplatePlaceholders -Text $out -NewPkg $NewPkg
    $out = Set-ProcToBlockDefault -Text $out
    # Never ship blank/'{Typ}' GPF wrapper values (Freia/Gandalf fresh-build findings).
    $out = Set-GpfWrapperDefaults -Text $out -NewPkg $NewPkg -IsMsi ([bool]($NewPkg.ProductCode -or $NewPkg.MsiFileName))
    # Final enforcement of the GPF SoftIdent convention (wrapper PLAIN, x86-only tokened copy in CUSTOM VARIABLES).
    $out = Set-GpfSoftIdentTwoPlace -Text $out -Arch "$($NewPkg.Arch)" -Version "$($NewPkg.Version)"
    # BRAND RULES: Audi (INA) closes processes silently (ProcToClose -> ProcToCloseNonUI); Group (VWG) 34-char name gate.
    $gpfBrand = Get-GpfTargetBrand -NewPkg $NewPkg
    $out = Set-GpfProcToCloseNonUI -Text $out -Brand $gpfBrand
    if ($gpfBrand -eq 'VWG') { $vwgLen = Get-GpfVwgNameLength -NewPkg $NewPkg; if ($vwgLen -gt 34) { Write-Log "Group (VWG) name is $vwgLen chars - exceeds the 34-character limit (Manufacturer+Product+Version+Language). Shorten the name." Warning } }
    return (Format-OutputScript -Text $out)
}

##############################################################
# Build-PredecessorScript - the pipeline.
#   $Model    : from Read-PredecessorModel (predecessor)
#   $NewPkg    : @{ Version; ProductCode; MsiFileName; ExeFileName; SoftIdent; ... }  (current app)
#   $Template  : fresh CURRENT v4 template script text
#   $AddUninstallPrevious : include the predecessor-uninstall block (default $true)
##############################################################
# Detect the predecessor-of-predecessor version from a script body: the highest version, strictly OLDER than the
# predecessor, that appears in a package-identity detection key ({Vendor}_{App}_{Arch}_<ver>-...). Returns $null when
# there is no such older reference (a first-generation package, or a vendor that doesn't carry previous-version checks).
function Get-PredecessorOfPredecessorVersion {
    param([string]$Text, [hashtable]$Identity, [string]$PredVersion)
    if (-not $Text -or -not $Identity) { return $null }
    $pv = try { [version]("$PredVersion" -replace '[^0-9.]','') } catch { $null }
    if (-not $pv) { return $null }
    $prefix = "$($Identity.Vendor)_$($Identity.AppName)_$($Identity.Arch)_"
    $pat = [regex]::Escape($prefix) + '(?<ver>\d+(?:\.\d+)+)-'
    $best = $null; $bestV = $null
    foreach ($m in [regex]::Matches($Text, $pat)) {
        $vs = $m.Groups['ver'].Value
        $vv = try { [version]($vs -replace '[^0-9.]','') } catch { $null }
        if (-not $vv) { continue }
        if ($vv -lt $pv -and (-not $bestV -or $vv -gt $bestV)) { $bestV = $vv; $best = $vs }
    }
    return $best
}

# LOG-PATH FORMAT modernisation (team convention). OLD (v3): a flat log dir + per-purpose log FILE names -
#   [string]$setuplogName = $VWG_appFullName + "_Setup_" + $deploymentType + ".log"   ... used as "$configToolKitLogDir\$setuplogName".
# NEW (v4): a per-app log DIRECTORY built from Get-ADTConfig, defined in EACH section that logs, and referenced as $LogPathMain:
#   $adtConfig = Get-ADTConfig
#   New-ADTFolder -Path "$($adtConfig.Toolkit.LogPath)\$($adtSession.AppVendor)\$($adtSession.AppName)_$($adtSession.AppVersion)\$($adtSession.DeploymentType)"
#   $LogPathMain = "...same..."
# This: (1) drops the [string]$setuplogName* declarations, (2) rewrites every "$configToolKitLogDir\$setuplogName*" (and
# any bare $configToolKitLogDir / standalone $setuplogName*) to $LogPathMain, (3) injects the definition block at the top
# of each section that now references $LogPathMain. No-op when the script doesn't use the old format.
function Convert-LogPathFormat {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if ($Text -notmatch '(?i)\$configToolKitLogDir' -and $Text -notmatch '(?i)\$setuplogName') { return $Text }
    $t = $Text
    # 1. Drop the old declaration lines: [string]$setuplogName<any> = ...
    $t = [regex]::Replace($t, '(?im)^[ \t]*\[string\][ \t]*\$setuplogName\w*[ \t]*=.*\r?\n?', '')
    # 2a. "$configToolKitLogDir\$setuplogName<var>"  ->  $LogFileMain   (the COMMON case: the whole flat log-FILE path).
    #     MUST be the FILE variable, not $LogPathMain (a DIRECTORY) - pointing an installer's -Log/-LogFileName at a
    #     directory only creates the folder, no log file (the reported bug).
    $t = [regex]::Replace($t, '(?i)\$configToolKitLogDir\\\$setuplogName\w*', '$LogFileMain')
    # 2b. any remaining bare $configToolKitLogDir (e.g. nested "$configToolKitLogDir\$logfolder\...")  ->  $LogPathMain (dir).
    #     Do this BEFORE 2c so a nested path keeps its subfolder ($LogPathMain\$logfolder\...).
    $t = [regex]::Replace($t, '(?i)\$configToolKitLogDir', '$LogPathMain')
    # 2c. any standalone $setuplogName<var> left (used as a FILENAME inside a nested path, e.g. $LogPathMain\$logfolder\...)
    #     -> a real v4 log FILENAME literal. NOT $LogFileMain (a full path) - that would double the directory in a nested case.
    $t = [regex]::Replace($t, '(?i)\$setuplogName\w*', '$($adtSession.AppName)_$($adtSession.AppVersion)_$($adtSession.DeploymentType).log')
    if ($t -notmatch '\$LogPathMain' -and $t -notmatch '\$LogFileMain') { return $t }
    # 3. Inject log-path definitions into the sections that log. Pre/Main/Post of ONE deployment run share the SAME function
    #    scope (Install-ADTDeployment / Uninstall-ADTDeployment / Repair-ADTDeployment), so the folder + $LogPathMain are
    #    defined ONCE (first logging section of each Install/Uninstall/Repair GROUP) and REUSED; later sections in the same
    #    group only set the phase-specific $LogFileMain. Uninstall/Repair are separate functions -> each gets its own scaffold.
    #    $LogFileMain name carries the SECTION PHASE (_Setup_PreInstall.log vs _Setup_Install.log), and reuses the template's
    #    $AppFullName (Vendor_App_Arch_Version-Rev_Lang) - not a rebuilt identity.
    $phaseMap = @{ PreInstallCode='PreInstall'; MainInstallCode='Install'; PostInstallCode='PostInstall'
                   PreUninstallCode='PreUninstall'; MainUninstallCode='Uninstall'; PostUninstallCode='PostUninstall'
                   PreRepairCode='PreRepair'; MainRepairCode='Repair'; PostRepairCode='PostRepair' }
    $groupMap = @{ PreInstallCode='Install'; MainInstallCode='Install'; PostInstallCode='Install'
                   PreUninstallCode='Uninstall'; MainUninstallCode='Uninstall'; PostUninstallCode='Uninstall'
                   PreRepairCode='Repair'; MainRepairCode='Repair'; PostRepairCode='Repair' }
    $scaffoldTemplate = @'
        $adtConfig = Get-ADTConfig
        $LogPathMain = "$($adtConfig.Toolkit.LogPath)\$($adtSession.AppVendor)\$($adtSession.AppName)_$($adtSession.AppVersion)\$($adtSession.DeploymentType)"
        New-ADTFolder -Path $LogPathMain
        $LogFileMain = "$LogPathMain\$($AppFullName)_Setup_@@PHASE@@.log"
'@ -replace "`r?`n", "`r`n"
    $lineTemplate = '        $LogFileMain = "$LogPathMain\$($AppFullName)_Setup_@@PHASE@@.log"'   # scaffold already defined in this function -> just the file name
    $groupScaffolded = @{}
    foreach ($s in $script:SectionMarkers) {
        if ($s.F -eq 'CustomVariables') { continue }
        $mB = [regex]::Match($t, $s.B); $mE = [regex]::Match($t, $s.E)
        if (-not $mB.Success -or -not $mE.Success -or $mE.Index -le $mB.Index) { continue }
        $bodyStart = $mB.Index + $mB.Length
        $body = $t.Substring($bodyStart, $mE.Index - $bodyStart)
        if ($body -notmatch '\$LogPathMain' -and $body -notmatch '\$LogFileMain') { continue }   # section doesn't log -> nothing
        $group = $groupMap[$s.F]; if (-not $group) { $group = "$($s.F)" }
        if ($body -match '(?i)\$adtConfig\s*=\s*Get-ADTConfig') { $groupScaffolded[$group] = $true; continue }   # already defined (re-run)
        $phase = $phaseMap[$s.F]; if (-not $phase) { $phase = 'Main' }
        if ($groupScaffolded[$group]) {
            $block = $lineTemplate.Replace('@@PHASE@@', $phase)                     # reuse $LogPathMain from the earlier section
        } else {
            $block = $scaffoldTemplate.Replace('@@PHASE@@', $phase)                 # first logging section of the group -> full scaffold
            $groupScaffolded[$group] = $true
        }
        $t = $t.Substring(0, $bodyStart) + "`r`n" + $block + $t.Substring($bodyStart)
    }
    return $t
}

function Build-PredecessorScript {
    param(
        [hashtable]$Model,
        [hashtable]$NewPkg,
        [string]$Template,
        [bool]$AddUninstallPrevious = $true
    )
    $predVer = "$($Model.Identity.Version)"
    $newVer  = "$($NewPkg.Version)"

    # Build the OLD->NEW swap map (filenames, MSTs, ProductCodes). Three cases:
    #   MULTI: pair the predecessor's install SEQUENCE with the new package's installers BY ORDER and swap EVERY
    #          component (filename + MST + ProductCode) - a version update keeps the same components in the same order.
    #   SINGLE: swap the one primary installer's filename/MST/ProductCode.
    #   else  : type mismatch / unknown -> carry commands verbatim (version pass still runs), flagged for manual review.
    $newType = if ($NewPkg.MsiFileName) { 'MSI' } elseif ($NewPkg.ExeFileName) { 'EXE' }
               elseif (@($NewPkg.Installers).Count -gt 0) { 'Multiple' } else { 'None' }
    $predSeq = @($Model.InstallSeq)
    $newInst = @($NewPkg.Installers)
    $swapMap = @{}
    $doInstallerSwap = $false
    if ($newType -eq 'Multiple' -and $predSeq.Count -gt 1 -and $newInst.Count -eq $predSeq.Count) {
        $doInstallerSwap = $true
        for ($i = 0; $i -lt $predSeq.Count; $i++) {
            $o = $predSeq[$i]; $n = $newInst[$i]
            $nName = "$(if ($n.MsiFileName) { $n.MsiFileName } elseif ($n.ExeFileName) { $n.ExeFileName } else { '' })"
            if ("$($o.Name)".Trim() -and $nName) { $swapMap["$($o.Name)"] = $nName }
            if ("$($o.Mst)".Trim() -and $n.MsiFileName) { $swapMap["$($o.Mst)"] = ([IO.Path]::GetFileNameWithoutExtension($n.MsiFileName) + '.mst') }
            if ("$($o.ProductCode)".Trim() -and "$($n.ProductCode)".Trim()) { $swapMap["$($o.ProductCode)"] = "$($n.ProductCode)" }
        }
        Write-Log "Predecessor multi-component: paired $($predSeq.Count) installer(s) by order - swapped every filename + MST + ProductCode."
    } elseif ($newType -ne 'None' -and $newType -eq $Model.Installer.Type) {
        $doInstallerSwap = $true
        if ($Model.Installer.MsiFileName -and $NewPkg.MsiFileName) {
            $swapMap[$Model.Installer.MsiFileName] = $NewPkg.MsiFileName
            $swapMap[([IO.Path]::GetFileNameWithoutExtension($Model.Installer.MsiFileName) + '.mst')] = ([IO.Path]::GetFileNameWithoutExtension($NewPkg.MsiFileName) + '.mst')
        }
        if ($Model.Installer.ExeFileName -and $NewPkg.ExeFileName) { $swapMap[$Model.Installer.ExeFileName] = $NewPkg.ExeFileName }
        if ($Model.Installer.ProductCode -and $NewPkg.ProductCode) { $swapMap[$Model.Installer.ProductCode] = $NewPkg.ProductCode }
        # An MSI installed BY FILE (Start-ADTMsiProcess -FilePath x.msi) carries NO ProductCode on the INSTALL line - the
        # code only lives in the UNINSTALL section (-ProductCode {GUID}) and the SoftIdent detection key. Add THAT code to
        # the swap as well, so the new package UNINSTALLS and DETECTS the NEW version's ProductCode, not the predecessor's.
        if ($NewPkg.ProductCode) {
            $unPC = Get-PredecessorUninstallPC -Model $Model
            if ($unPC -and $unPC -ne "$($NewPkg.ProductCode)") { $swapMap[$unPC] = "$($NewPkg.ProductCode)" }
        }
    } else {
        Write-Log "Source type ($newType) != predecessor ($($Model.Installer.Type))$(if ($newType -eq 'Multiple' -and $predSeq.Count -ne $newInst.Count) { " or component count differs ($($predSeq.Count) vs $($newInst.Count))" }) - carrying commands verbatim, fields still populated; verify each command." Warning
    }
    # SAFETY NET: the later version pass rewrites old-version digits ANYWHERE, including inside a not-yet-swapped
    # name. If that happens before/around the literal swap, the original key no longer matches and the OLD ref
    # silently survives. So also map the VERSION-SWAPPED variant of every old key to the same new value.
    if ($doInstallerSwap) {
        $pv = "$($Model.Identity.Version)"; $nv = "$($NewPkg.Version)"
        if ($pv -and $nv -and $pv -ne $nv) {
            foreach ($k in @($swapMap.Keys)) {
                $kv = Invoke-VersionSwap -Text $k -OldVersion $pv -NewVersion $nv
                if ($kv -ne $k -and -not $swapMap.ContainsKey($kv)) { $swapMap[$kv] = $swapMap[$k] }
            }
        }
    }

    # 1. Inject authored bodies into the fresh template.
    #    The predecessor's OWN existing uninstall block (which removes ITS predecessor,
    #    i.e. the older version) is excised here but PRESERVED verbatim. It is already
    #    pinned to its target version and already v4-converted, so we keep it as-is and
    #    re-inject it as the older of the two accumulated blocks (Plan section 2).
    $preservedOldBlocks = New-Object System.Collections.Generic.List[string]
    # The team labels this group with a "## Uninstallation of predecessor package" comment.
    # We re-emit it (CORRECTED spelling) as the header above the blocks and strip the
    # predecessor's own copy (incl. the "Uninsallation" typo) so it is not left orphaned.
    $uninstallHeader = '## Uninstallation of predecessor package'
    $out = $Template
    # GPF PREDECESSOR REUSE (team decision): for the MAIN sections, use whatever the predecessor authored (its own log
    # lines, already v4-converted) and REMOVE our v4 template's Start/Installation-of scaffold logs - so the section reads
    # exactly like the hand-authored predecessor, with no duplicated template logs (iDEX finding). Passed to Set-SectionBody
    # as $DropTemplateLogs below, ONLY for Main-Install/Uninstall/Repair. (Pre/Post keep the template scaffolding.)
    $isGpfReuse = (Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF'
    foreach ($s in $script:SectionMarkers) {
        $body = "$($Model.Code.$($s.F))"
        if ($s.F -eq 'PreInstallCode') {
            # SEPARATE between-code handling (does NOT change the uninstall logic): the custom code BETWEEN the template's
            # reboot-check and user-dialogs blocks is carried VERBATIM and is NEVER counted as a predecessor uninstall
            # block (user rule) - so the uninstall-chain extraction / self-uninstall-guard removal run ONLY on the REST
            # (the code below the dialogs). The dialogs position is marked by '#__PB_DIALOGS_SPLIT__'. Everything the
            # extraction does to the REST is exactly the original working behaviour; the between-code is simply set aside.
            $splitTok = '#__PB_DIALOGS_SPLIT__'
            $sx = $body.IndexOf($splitTok)
            $between = if ($sx -ge 0) { $body.Substring(0, $sx) } else { '' }
            $rest    = if ($sx -ge 0) { $body.Substring($sx) } else { $body }   # sentinel stays at the front of $rest
            # Extract EVERY existing uninstall block from the REST (the predecessor's own chain) so the later version swap
            # can't touch them; they are re-inserted verbatim below (ALWAYS - regardless of the $AddUninstallPrevious checkbox).
            $split = Split-ExistingUninstallBlocks -Code $rest -Identity $Model.Identity
            foreach ($b in $split.Blocks) { $preservedOldBlocks.Add($b) }
            $rest = $split.Body
            $rest = [regex]::Replace($rest, '(?im)^[ \t]*#+[ \t]*Unin\w*ation of predecessor package[^\r\n]*\r?\n?', '')
            # Drop the predecessor's bare "##Uninstalling <...> if present" self-uninstall guard (redundant with the
            # generated immediate-predecessor block; on reuse it reads as a current-version uninstall in pre-install).
            $rest = Remove-SelfUninstallGuard -Body $rest
            # Split-ExistingUninstallBlocks .Trim()s its Body, which would drop the leading sentinel; re-attach it so
            # Set-SectionBody can still tell above-dialogs from below-dialogs. Between-code is left completely untouched.
            if ($sx -ge 0 -and "$rest" -notmatch [regex]::Escape($splitTok)) { $rest = $splitTok + "`r`n" + $rest }
            $body = "$between" + "$rest"
        }
        if ($s.F -in 'MainInstallCode','MainUninstallCode','MainRepairCode','PreRepairCode') {
            # PreRepair is the "uninstall-then-reinstall" of the CURRENT package, so its ProductCode/filenames must be
            # the NEW ones too (a repair that uninstalled the OLD code would target the wrong version).
            $body = Swap-InstallerRefs -Body $body -Map $swapMap
        }
        # POST-UNINSTALLATION: the template owns the branding removal; the predecessor's copy
        # is dropped here (it survives only inside the uninstall-previous block, below).
        if ($s.F -eq 'PostUninstallCode') {
            $body = Remove-SectionBrandingUninstall -Body $body
        }
        # PRE-REPAIR: never remove branding / reboot here (it's just uninstall-before-reinstall).
        if ($s.F -eq 'PreRepairCode') {
            $body = Remove-PreRepairNoise -Body $body
        }
        $dropLogs = $isGpfReuse -and ($s.F -in 'MainInstallCode','MainUninstallCode','MainRepairCode')
        $out = Set-SectionBody -Template $out -Begin $s.B -End $s.E -Body $body -Pre $s.Pre -DropTemplateLogs $dropLogs
    }

    # 2. Session block. The (blank) template's $adtSession is replaced by the predecessor's
    #    whole block (carries all MTB config - ProcToClose, FreeSpace, SoftIdent, dialogs),
    #    then identity is retargeted to the NEW package. AppVersion = NEW.
    # DeployAppScriptVersion is the TOOLKIT version that ships with OUR template (e.g. 4.1.8) -
    # it must NOT inherit the predecessor's older value, so capture the template's and restore it.
    $tplDeployVer = [regex]::Match($Template, "(?m)DeployAppScriptVersion\s*=\s*'([^']*)'").Groups[1].Value
    $predSession = Get-AdtSessionBlock -Text "$($Model.RawV4Content)"
    if ($predSession) { $out = Set-AdtSessionBlock -Template $out -NewBlock $predSession }
    if ($tplDeployVer) { $out = Set-SessionField $out 'DeployAppScriptVersion' $tplDeployVer }
    # MTB values pulled from the predecessor (covers v3, where there is no $adtSession block to swap).
    if ($Model.Session) {
        foreach ($sf in 'ProcToClose','ProcToCloseNonUI','ProcToBlock','FreeSpace','FreeSpaceUninst','SoftIdent','CheckForReboot','AllowDefer','ShowBalloonTips',
                        'SoftinstTyp','Portfv','AppAddInfo01','AppAddInfo02','AppAddInfo03','AppAddInfo04') {
            if (-not $Model.Session.ContainsKey($sf)) { continue }
            if ($sf -eq 'ProcToClose') {
                # GPF template: $adtSession.AppProcessesToClose is the AUTHORITATIVE list, and the wrapper line
                # "[string[]] $Global:VWG_ProcToClose = $adtSession.AppProcessesToClose" is a BRIDGE that must stay
                # (an empty AppProcessesToClose is perfectly valid). Fill AppProcessesToClose; only when that field
                # does not exist (MTB template) fall back to the direct ProcToClose fill.
                $try = Set-SessionValue -Text $out -Field 'AppProcessesToClose' -Value $Model.Session[$sf]
                if ($try -ne $out) { $out = $try; continue }
            }
            $out = Set-SessionValue -Text $out -Field $sf -Value $Model.Session[$sf]
        }
    }
    foreach ($f in @('AppVendor','Vendor'),@('AppName','AppName'),@('AppArch','Arch'),
                   @('AppLang','Lang'),@('AppRevision','Revision'),@('OrderNumber','Ritm'),
                   @('AppScriptAuthor','Author')) {
        $out = Set-SessionField $out $f[0] "$($NewPkg[$f[1]])"
    }
    $out = Set-SessionField $out 'AppScriptDate'   (Get-Date -Format 'yyyy-MM-dd')
    $out = Set-SessionField $out 'AppScriptAuthor' (Format-AuthorName "$($NewPkg.Author)")
    $out = [regex]::Replace($out, "(?m)(AppVersion\s*=\s*')[^']*(')", "`${1}$newVer`${2}")
    # GPF: InstallTitle = 'Vendor AppName Version' (their house style). On REUSE, carry the predecessor's InstallTitle
    # STYLE - specifically a trailing architecture suffix like " (x86)" / " (x64)" (finding: "take InstallTitle style
    # from predecessor package if available"). The NEW vendor/app/version are used; only the parenthetical suffix is kept.
    if ((Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') {
        $predTitle  = [regex]::Match("$($Model.RawV4Content)", "(?im)InstallTitle\s*=\s*'([^']*)'").Groups[1].Value
        $titleSuffix = [regex]::Match($predTitle, '\s*(\([^)]*\))\s*$').Groups[1].Value
        $newTitle   = "$($NewPkg.Vendor) $($NewPkg.AppName) $newVer".Trim()
        if ($titleSuffix) { $newTitle = "$newTitle $titleSuffix" }
        $out = Set-SessionField $out 'InstallTitle' $newTitle
        # HEADS-UP (#13/Point2): if the packager selected VW but this is a REUSE, the VW "Volkswagen" title rule is NOT
        # applied - we keep the predecessor's own install title. Surface this prominently so the packager knows WHY.
        if ((Get-GpfTargetBrand -NewPkg $NewPkg) -eq 'G1V') {
            Add-GpfNotice ("VW 'Volkswagen' install-title rule was NOT applied: this is a predecessor REUSE, so the predecessor's install title was kept ('$newTitle'). The Volkswagen rule only applies to FRESH packages. Edit the InstallTitle by hand if you need it changed.")
        }
    }
    if ($NewPkg.SoftIdent) {
        $out = Set-SessionValue -Text $out -Field 'SoftIdent' -Value (Format-BrandSoftIdent -Value "$($NewPkg.SoftIdent)" -Arch "$($NewPkg.Arch)")
    } elseif ($newVer) {
        # Predecessor-carried SoftIdent (no new-version snapshot): bump its embedded [DisplayVersion=...] to the NEW version
        # DETERMINISTICALLY. The generic version swap can miss it because the predecessor's REAL DisplayVersion (e.g. Inno's
        # 4-part 3.5.17129.17210) differs from the predecessor PACKAGE version used as the swap token - so the detection
        # stayed pinned to the old version. This sets it to the new version regardless of the old string.
        $before = $out
        # MTB format: '... [DisplayVersion = 1.2.3]' (version INSIDE the brackets; line prefix covers the GPF wrapper
        # shape too; QUOTE-AGNOSTIC - GPF SoftIdent is double-quoted so $($VWG_CurrentRegWOW) interpolates)
        $out = [regex]::Replace($out, "(?im)(^[ \t]*[^\r\n'`"]*SoftIdent[ \t]*=[ \t]*['`"][^'`"]*\[DisplayVersion[ \t]*=[ \t]*)[^\]'`"]+(\])", "`${1}$newVer`${2}")
        # GPF format: '... [DisplayVersion]=26.01.00.0' (version AFTER the brackets, runs to the closing quote)
        $out = [regex]::Replace($out, "(?im)(^[ \t]*[^\r\n'`"]*SoftIdent[ \t]*=[ \t]*['`"][^'`"]*\[DisplayVersion\][ \t]*=[ \t]*)[^'`"\r\n]+(['`"])", "`${1}$newVer`${2}")
        if ($out -ne $before) { Write-Log "SoftIdent DisplayVersion bumped to the new version ($newVer) - predecessor-carried detection." Success }
    }
    # SoftIdent keeps the predecessor's hive/structure; swap its ProductCode old->new (version
    # is handled by the global swap). Detection blocks are injected LATER and keep the pred PC.
    $predPC = Get-PredecessorUninstallPC -Model $Model
    if (-not $predPC) { $predPC = "$($Model.Installer.ProductCode)" }
    if ($predPC -and $NewPkg.ProductCode -and $predPC -ne $NewPkg.ProductCode) {
        # quote-agnostic: GPF SoftIdent values are double-quoted (runtime WoW token), MTB single-quoted
        $out = [regex]::Replace($out, "(?m)$(Get-FieldLinePrefix 'SoftIdent')(['`"][^'`"]*)" + [regex]::Escape($predPC), "`${1}`${2}$($NewPkg.ProductCode)")
    }
    # SoftIdent hive must match the NEW package's bitness (predecessors sometimes carry the
    # wrong WoW6432Node segment). The separate [string]$VWG_SoftIdent custom variable is
    # legacy - drop it; SoftIdent now lives solely in $adtSession (MTB) / the wrapper line (GPF).
    $out = [regex]::Replace($out, "(?m)$(Get-FieldLinePrefix 'SoftIdent')'([^']*)(')",
        { param($m) $m.Groups[1].Value + "'" + (Normalize-SoftIdent -Value $m.Groups[2].Value -Arch "$($NewPkg.Arch)") + $m.Groups[3].Value })
    # Dropping the [string]$VWG_SoftIdent custom variable is an MTB-ONLY rule (SoftIdent moves into $adtSession
    # there). GPF predecessors legitimately (re)define it with the runtime WoW token in CUSTOM VARIABLES - KEEP it
    # (the PC/version swaps above are line-prefix based, so they update this line too).
    if ((Get-PBBrand -Path 'Name' -Default 'MTB') -ne 'GPF') {
        $out = [regex]::Replace($out, '(?im)^[ \t]*\[string\][ \t]*\$VWG_SoftIdent\b[^\r\n]*\r?\n?', '')
    }
    $out = Set-TemplatePlaceholders -Text $out -NewPkg $NewPkg

    # 3. PLAN SECTION 1 swap: predecessor version -> new version across the whole
    #    assembled script (catches version-named folders, SoftIdent literals, etc).
    #    Runs BEFORE the uninstall block is injected, so that block is never touched.
    $out = Invoke-VersionSwap -Text $out -OldVersion $predVer -NewVersion $newVer

    # 3b. NAME SWAP (user decision: reuse a predecessor whose app-name SEGMENT differs, e.g. Tenable
    #     NessusAgentRISLAPAC -> NessusAgentAS). Swap the predecessor's AppName -> the new package's AppName
    #     across the MAIN body (install/uninstall/repair logs + SoftIdent), so the CURRENT package never
    #     carries the predecessor's app name. Runs at the SAME point as the version swap - BEFORE the
    #     uninstall-previous blocks are (re)injected, which legitimately remove the OLD installed package by
    #     its REAL (predecessor) name and must keep it. One replace covers both the underscored full-name
    #     ("Vendor_App_Arch") and the spaced log ("Vendor App Version") forms - both embed the AppName token.
    $predApp = "$($Model.Identity.AppName)"; $newApp = "$($NewPkg.AppName)"
    if ($predApp -and $newApp -and $predApp -ne $newApp) {
        $out = $out.Replace($predApp, $newApp)
        Write-Log "Name swap: predecessor app '$predApp' -> '$newApp' across the current package's body." Success
    }


    # 4. PLAN SECTION 2 (accumulate): up to TWO predecessor uninstall blocks, so the new
    #    package removes whichever of the last two versions is found in the field (mirrors
    #    real packages, e.g. Synera, which stacks two blocks). Both are injected AFTER the
    #    global version swap, so neither is bumped - every block stays pinned to the version
    #    it removes.
    #      Older block = the predecessor's OWN existing block, kept verbatim.
    #      Newer block = remove THIS predecessor, generated from its identity the same way
    #                    we generate one when none exists (branding key + ProductCode/Name,
    #                    body = predecessor Pre+Main+Post uninstall), pinned to v$predVer.
    #    Order: older first, then newer (ascending), both before the install.
    $s = $script:SectionMarkers | Where-Object F -eq 'PreInstallCode' | Select-Object -First 1
    $blocks = New-Object System.Collections.Generic.List[string]

    # The predecessor's OWN existing uninstall block(s) remove the PREDECESSOR-OF-PREDECESSOR (older versions).
    # MTB stacks up to two blocks (e.g. Synera) so it keeps them verbatim. GPF wants ONLY the immediate predecessor
    # uninstalled (team decision: "don't want predecessor-of-predecessor code to be there") - so for GPF we DROP the
    # preserved older block(s) and rely solely on the generated immediate-predecessor block below.
    $gpfImmediateOnly = (Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF'
    if ($gpfImmediateOnly) {
        if ($preservedOldBlocks.Count -gt 0) { Write-Log "Uninstall-prev: DROPPED $($preservedOldBlocks.Count) predecessor-of-predecessor block(s) - GPF keeps only the immediate predecessor uninstall." Warning }
    } else {
        foreach ($b in $preservedOldBlocks) { $blocks.Add($b) }
        if ($preservedOldBlocks.Count -gt 0) { Write-Log "Uninstall-prev: kept $($preservedOldBlocks.Count) existing predecessor uninstall block(s) verbatim." Success }
    }
    if ($AddUninstallPrevious) {
        $blocks.Add((New-UninstallPreviousBlock -Model $Model -WrapperLine $null).Trim())
        Write-Log "Uninstall-prev: added generated block for immediate predecessor v$predVer." Success
    } else {
        Write-Log "Uninstall-prev: opted out of a NEW block - kept the predecessor's own uninstall block(s) untouched." Warning
    }
    if ($blocks.Count -gt 0) {
        # Header first, then the blocks (so the comment heads the group, not trails it).
        $group = $uninstallHeader + "`r`n" + ($blocks -join "`r`n`r`n")
        $out = Insert-IntoPreInstall -Script $out -Section $s -Block $group
    }

    # 4b. PREDECESSOR-OF-PREDECESSOR bump - ONLY when uninstall-previous is UNCHECKED (user rule). Two modes:
    #       CHECKED  (AddUninstallPrevious=$true): STANDARD behaviour - keep the predecessor's own block verbatim AND add
    #                our generated "remove the predecessor" block. The predecessor's previous-version refs (e.g. nCode's
    #                "if 2023.1 installed...") stay pinned - two stacked blocks give multi-version coverage. NO bump.
    #       UNCHECKED(AddUninstallPrevious=$false): we add NO generated block, so the ONLY previous-version handling is
    #                the predecessor's own logic - which still targets TWO versions back (23). Bump it up ONE step
    #                (pred-of-pred -> predecessor, 23.1 -> 24.1) so the kept script's "previous version" = the immediate
    #                predecessor (24), matching the new package. Runs LAST (covers main body + preserved block); only
    #                turns 23.x -> 24.x, never the predecessor(24)/new(26) refs; bare years/dates/copyrights are safe.
    if (-not $AddUninstallPrevious) {
        $predPredVer = Get-PredecessorOfPredecessorVersion -Text $out -Identity $NewPkg -PredVersion $predVer
        if ($predPredVer) {
            $out = Invoke-VersionSwap -Text $out -OldVersion $predPredVer -NewVersion $predVer
            Write-Log "Pred-of-pred bump (uninstall-previous UNCHECKED): '$predPredVer' references moved up to the predecessor '$predVer'." Warning
        }
    }

    # Collapse any reused verbose branding-removal calls (e.g. inside the preserved old
    # uninstall block) to the short positional form.
    $out = Simplify-RemoveDetectionKey -Text $out
    # A repair MSI call needs an explicit -RepairMode 'Repair'. Add it to any
    # Start-ADTMsiProcess -Action 'Repair' that is missing it (idempotent).
    $out = [regex]::Replace($out,
        "(?im)(Start-ADTMsiProcess\b[^\r\n]*?-Action\s+'?Repair'?)(?!\s+-RepairMode)",
        "`${1} -RepairMode 'Repair'")
    # PLAN: PSADT v4 scope auto-fix. Relocate CUSTOM-VARIABLES lines that read the live session
    # (DeploymentType / ADT $env* / $config*) into each action's PRE-section, where those values exist
    # (in the variables block they are empty on v4). Proven 0 parse breaks across the corpus.
    # BRAND-GATED (SectionVarScope): the GPF template opens the ADT session BEFORE the custom-variables
    # region, so session/env values are LIVE there - custom variables stay ONCE, exactly as authored.
    $doScopeFix = if (Get-Command Test-PBConvertFlag -ErrorAction SilentlyContinue) { Test-PBConvertFlag 'SectionVarScope' } else { $true }
    # belt-and-braces: NEVER scope-move for the GPF brand, even when the flag is missing from an older settings.json
    if ((Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') { $doScopeFix = $false }
    if ($doScopeFix) {
        $mv = Move-V4RuntimeVars -ScriptText $out
        if (@($mv.Moved).Count -gt 0) { $out = $mv.Text; Write-Log "v4 scope fix: moved $(@($mv.Moved).Count) variable(s) from CUSTOM VARIABLES into the Install/Uninstall/Repair sections." }
    }
    # SNAPSHOT-ASSISTED REUSE: the predecessor's OWN authored install/uninstall/repair logic is carried verbatim (above);
    # here we ADDITIVELY merge what the NEW version's snapshot reveals that the predecessor lacks - net-new cleanups, a
    # bigger FreeSpace footprint, a fresher detection key, and any new app processes - de-duplicated so nothing the
    # predecessor already does is touched or duplicated. (Per-user config is still left to snippets in reuse mode.)
    $out = Merge-SnapshotDeltas -Text $out -NewPkg $NewPkg -Model $Model
    $out = Set-ProcToBlockDefault -Text $out
    # F52: carry the installation progress bar when the predecessor had it enabled (section-scoped, review-flagged).
    $pb = Set-PredecessorProgressBar -Text $out -Model $Model
    $out = $pb.Text
    # LOG-PATH FORMAT (MTB team convention, ~half of live v3 packages): the old flat "$configToolKitLogDir\$setuplogName"
    # scheme is replaced by the new per-app v4 log dir ($LogPathMain, defined via Get-ADTConfig in each section).
    # BRAND-GATED: the GPF template handles LogName itself ($configToolkitLogDir maps to $adtConfig.Toolkit.LogPath there).
    $doLogFmt = if (Get-Command Test-PBConvertFlag -ErrorAction SilentlyContinue) { Test-PBConvertFlag 'LogPathMain' } else { $true }
    if ($doLogFmt) { $out = Convert-LogPathFormat -Text $out }
    # GPF: when the predecessor carries its OWN active reboot handler (e.g. "if ($exit_code.ExitCode -eq '3010')
    # { Set-Reboot }"), the template's placeholder pair ("##Handling for required reboot" + "#Set-Reboot") in the
    # SAME section is redundant - the carried handler REPLACES it.
    if ((Get-Command Get-PBBrand -ErrorAction SilentlyContinue) -and (Get-PBBrand -Path 'Name' -Default 'MTB') -eq 'GPF') {
        $out = Remove-GpfRebootPlaceholder -Text $out
        # Flag-logic branding removal (team finding + gold standard): when the Uninstall function conditionally
        # uninstalls the predecessor's own exe (sets $flag=$true), the Post-Uninstall branding removal must be
        # GUARDED by If($flag) - not run unconditionally, and not left as a dead empty If($flag){}.
        $out = Set-GpfFlagGuardedBranding -Text $out -Model $Model
        # Reboot handler LAST in every section: after branding is finalised, move any carried Set-Reboot / soft-reboot
        # block to trail "## Branding Install / Set-Branding" (team rule: Set-Reboot is always the last statement).
        $out = Move-GpfRebootLast -Text $out
    }
    # Backstop: fill any GPF wrapper value the predecessor didn't carry (e.g. a v3 predecessor with no
    # SoftinstTyp/Portfv line), so we never ship '{Typ}'/'' - only touches values still blank.
    $out = Set-GpfWrapperDefaults -Text $out -NewPkg $NewPkg -IsMsi ([bool]($NewPkg.ProductCode -or $NewPkg.MsiFileName -or (Get-PredecessorUninstallPC -Model $Model)))
    # Same SoftIdent convention on the REUSE path: a predecessor that hardcoded WoW6432Node (or carried the token in
    # the wrapper) is normalised to wrapper-PLAIN + x86-only tokened copy in CUSTOM APPLICATION VARIABLES.
    $out = Set-GpfSoftIdentTwoPlace -Text $out -Arch "$($NewPkg.Arch)" -Version "$($NewPkg.Version)"
    # BRAND RULES (reuse): Audi (INA) closes processes silently (ProcToClose -> ProcToCloseNonUI); Group (VWG) name gate.
    $gpfBrand = Get-GpfTargetBrand -NewPkg $NewPkg
    $out = Set-GpfProcToCloseNonUI -Text $out -Brand $gpfBrand
    if ($gpfBrand -eq 'VWG') { $vwgLen = Get-GpfVwgNameLength -NewPkg $NewPkg; if ($vwgLen -gt 34) { Write-Log "Group (VWG) name is $vwgLen chars - exceeds the 34-character limit (Manufacturer+Product+Version+Language). Shorten the name." Warning } }
    $out = Format-OutputScript -Text $out
    Write-Log "Built predecessor script: v$predVer -> v$newVer, installerSwap=$doInstallerSwap, uninstallPrev=$AddUninstallPrevious" Success
    return $out
}

# GPF flag-logic: guard the Post-Uninstall branding removal with If($flag). The gold standard is
#   If($flag) { ## Branding Uninstall; Remove-Branding }   (branding removed ONLY when the predecessor's
# own uninstall actually ran). Assembly leaves the template's UNCONDITIONAL "## Branding Uninstall / Remove-Branding"
# plus a dead empty "If($flag){}" (the predecessor's guarded copy had its branding stripped as boilerplate). This
# drops the empty guard and wraps the template's branding removal in If($flag). Only fires when the Uninstall
# function actually sets $flag (packages that always remove branding are left unconditional).
function Set-GpfFlagGuardedBranding {
    param([string]$Text, [hashtable]$Model)
    if ($Text -notmatch '(?im)^[ \t]*\$flag\s*=\s*\$true') { return $Text }
    $mk = if (Get-Command Get-PBMarkerSet -ErrorAction SilentlyContinue) {
        Get-PBMarkerSet -Content $Text | Where-Object { $_.F -eq 'PostUninstallCode' } | Select-Object -First 1
    } else { $script:SectionMarkers | Where-Object { $_.F -eq 'PostUninstallCode' } | Select-Object -First 1 }
    if (-not $mk) { return $Text }
    $m = [regex]::Match($Text, "(?s)($($mk.B))(.*?)($($mk.E))")
    if (-not $m.Success) { return $Text }
    $body = $m.Groups[2].Value
    if ($body -notmatch '(?im)^[ \t]*Remove-Branding\b') { return $Text }   # nothing to guard
    if ($body -match '(?is)If\s*\(\s*\$flag\s*\)\s*\{[^}]*Remove-Branding') { return $Text }   # already guarded
    # MATCH THE PREDECESSOR (finding: don't add the If($flag) guard unnecessarily). Only WRAP the branding when the
    # PREDECESSOR itself guarded its branding with If($flag); if the predecessor had branding BARE, leave it bare here.
    # The branding/reboot ORDER is untouched (that is Move-GpfRebootLast's job) - we only decide whether to add the guard.
    # Always drop a dead empty "If ($flag) { }" either way.
    $predGuarded = $Model -and ("$($Model.RawV4Content)" -match '(?is)If\s*\(\s*\$flag\s*\)\s*\{[^}]*Remove-Branding')
    # 1. drop a dead empty "If ($flag) { }"
    $body = [regex]::Replace($body, '(?is)[ \t]*If\s*\(\s*\$flag\s*\)\s*\{\s*\}[ \t]*\r?\n?', '')
    # 2. wrap the template's "## Branding Uninstall" + "Remove-Branding" pair in an If($flag) guard ONLY when the
    #    predecessor guarded it (Invoke-Formatter re-indents).
    if ($predGuarded) {
        $body = [regex]::Replace($body, '(?im)^[ \t]*##[ \t]*Branding Uninstall[^\r\n]*\r?\n[ \t]*Remove-Branding\b[^\r\n]*',
            [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) "If (`$flag)`r`n{`r`n    ## Branding Uninstall`r`n    Remove-Branding`r`n}" })
    }
    return $Text.Remove($m.Index, $m.Length).Insert($m.Index, $m.Groups[1].Value + $body + $m.Groups[3].Value)
}

# GPF gold standard / team rule: within each section a reboot handler CARRIED FROM THE PREDECESSOR must be the LAST
# statement - AFTER "## Branding Install / Set-Branding" (and Post-Uninstall "Remove-Branding"). A predecessor that put
# its soft-reboot handler ("if ($exit_code.ExitCode -eq '3010') { Set-Reboot }"), a "## Handling for required reboot"
# placeholder, or a bare "Set-Reboot" BEFORE branding is reordered so reboot always trails branding. Safety: only a
# TOP-LEVEL (brace-depth 0) construct is moved - never a Set-Reboot nested in the uninstall-previous block or an
# "if ($VWG_CheckForReboot)" guard, and never the template's fixed "Set-Reboot -ForceExitScript" mandatory check.
# Idempotent (reboot already trailing branding = no branding after it = left untouched).
function Move-GpfRebootLast {
    param([string]$Text)
    $mkset = if (Get-Command Get-PBMarkerSet -ErrorAction SilentlyContinue) { Get-PBMarkerSet -Content $Text } else { $script:SectionMarkers }
    foreach ($s in $mkset) {
        if ($s.F -in @('CustomVariables','CustomFunctions')) { continue }
        $m = [regex]::Match($Text, "(?s)($($s.B))(.*?)($($s.E))")
        if (-not $m.Success) { continue }
        $body  = $m.Groups[2].Value
        $lines = @($body -split "`r?`n")
        # Brace depth at the START of each line (inline comments stripped) so we only ever act on a TOP-LEVEL (depth 0)
        # reboot construct - never a Set-Reboot nested inside the uninstall-previous block or an "if ($VWG_CheckForReboot)"
        # guard.
        $depthAt = New-Object 'int[]' $lines.Count
        $d = 0
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $depthAt[$i] = $d
            $code = ($lines[$i] -replace '#.*$','')
            foreach ($ch in $code.ToCharArray()) { if ($ch -eq '{') { $d++ } elseif ($ch -eq '}') { $d-- } }
        }
        # Locate the FIRST top-level reboot handler carried from the predecessor, in one of three forms:
        #   (a) the soft-reboot block   "if (... ExitCode ... 3010 ...) { ... Set-Reboot ... }"  (brace-balanced),
        #   (b) the template placeholder "## Handling for required reboot" + an ACTIVE Set-Reboot, or
        #   (c) a bare "Set-Reboot" - EXCLUDING the template's fixed "Set-Reboot -ForceExitScript ..." mandatory check.
        $start = -1; $end = -1; $isIf = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($depthAt[$i] -ne 0) { continue }
            if ($lines[$i] -match '(?i)^\s*if\b.*ExitCode.*3010') { $start = $i; $isIf = $true; break }
            if ($lines[$i] -match '(?i)^\s*#{1,2}\s*Handling for required reboot\b') {
                for ($n = $i + 1; $n -lt $lines.Count; $n++) {
                    if ($lines[$n] -notmatch '\S') { continue }
                    if ($lines[$n] -match '(?i)^\s*Set-Reboot\b') { $start = $i; $end = $n }   # active only (a commented #Set-Reboot leaves $start unset)
                    break
                }
                if ($start -ge 0) { break }
            }
            if ($lines[$i] -match '(?i)^\s*Set-Reboot\b' -and $lines[$i] -notmatch '(?i)-ForceExitScript') { $start = $i; $end = $i; break }
        }
        if ($start -lt 0) { continue }   # no movable reboot handler in this section
        # end line for the if-block form: brace-balance from the start line (inline comments ignored)
        if ($isIf) {
            $end = $start; $depth = 0; $seen = $false
            for ($j = $start; $j -lt $lines.Count; $j++) {
                $code = ($lines[$j] -replace '#.*$','')
                foreach ($ch in $code.ToCharArray()) { if ($ch -eq '{') { $depth++; $seen = $true } elseif ($ch -eq '}') { $depth-- } }
                $end = $j
                if ($seen -and $depth -le 0) { break }
            }
        }
        # pull in a directly-preceding REBOOT-related comment ("#Enabling Soft reboot if exit code is 3010")
        $cs = $start
        if ($cs -gt 0 -and $lines[$cs-1] -match '(?i)^\s*#.*reboot') { $cs = $start - 1 }
        # Reorder ONLY when a branding call (Set-Branding / Remove-Branding) appears AFTER the reboot block - i.e. reboot
        # is not yet "last after branding". If reboot already trails branding (or the section has none), leave it be.
        $brandAfter = $false
        for ($k = $end + 1; $k -lt $lines.Count; $k++) { if ($lines[$k] -match '(?i)^\s*(Set-Branding|Remove-Branding)\b') { $brandAfter = $true; break } }
        if (-not $brandAfter) { continue }
        $before = if ($cs -gt 0) { @($lines[0..($cs-1)]) } else { @() }
        $after  = if ($end + 1 -le $lines.Count - 1) { @($lines[($end+1)..($lines.Count-1)]) } else { @() }
        $block  = @($lines[$cs..$end])
        # Preserve the body's LEADING newline(s) (so the section marker never joins the first line); only collapse the
        # blank gap the moved block leaves behind, and trim the trailing newlines before re-appending the block.
        $keep   = [regex]::Replace((($before + $after) -join "`r`n"), "(\r?\n){3,}", "`r`n`r`n").TrimEnd("`r","`n")
        $newBody = $keep + "`r`n`r`n" + (($block -join "`r`n").Trim("`r","`n")) + "`r`n"
        $Text = $Text.Substring(0, $m.Groups[2].Index) + $newBody + $Text.Substring($m.Groups[2].Index + $body.Length)
    }
    return $Text
}

# Per marked section: an ACTIVE (uncommented) Set-Reboot carried from the predecessor supersedes the GPF template's
# commented placeholder ("##Handling for required reboot" + "#Set-Reboot") - remove the pair in that section only.
function Remove-GpfRebootPlaceholder {
    param([string]$Text)
    foreach ($s in $script:SectionMarkers) {
        if ($s.F -eq 'CustomVariables') { continue }
        $m = [regex]::Match($Text, "(?s)($($s.B))(.*?)($($s.E))")
        if (-not $m.Success) { continue }
        $body = $m.Groups[2].Value
        if ($body -notmatch '(?m)^[ \t]*Set-Reboot\b') { continue }   # no ACTIVE carried handler in this section
        $newBody = [regex]::Replace($body, '(?m)^[ \t]*#{1,2}\s*Handling for required reboot[^\r\n]*\r?\n([ \t]*#Set-Reboot[^\r\n]*\r?\n?)?', '')
        if ($newBody -ne $body) {
            $Text = $Text.Substring(0, $m.Groups[2].Index) + $newBody + $Text.Substring($m.Groups[2].Index + $body.Length)
        }
    }
    return $Text
}

##############################################################
# New-PackageMst - generate the MST for the CURRENT MSI using the
# selected checkboxes. Thin wrapper over the proven Build-Mst
# (MstBuilder.ps1). Plan sections 3 & 5: MSI desktop-shortcut /
# run-key removal happens here, in the MST - not in the script.
#   Returns the output .mst path, or $null if it could not run.
##############################################################
function New-PackageMst {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$AppName = '',
        [string]$ExistingMst,
        [bool]$RemoveDesktopShortcut = $false,
        [bool]$RemoveStartupShortcut = $false,
        [bool]$RemoveStrayShortcuts  = $false,
        [bool]$RemoveRunKey32 = $false,
        [bool]$RemoveRunKey64 = $false,
        [object[]]$ApplyExtras = @(),
        [hashtable]$Properties,
        $DeferredRunKeys   # optional List[object] - Build-Mst adds Run keys it couldn't safely remove in the MST (shared component) here, for PSADT post-install
    )
    if (-not (Get-Command Build-Mst -ErrorAction SilentlyContinue)) {
        Write-Log "Build-Mst not loaded (MstBuilder.ps1) - skipping MST." Warning; return $null
    }
    if (-not (Test-Path $MsiPath)) { Write-Log "MSI not found for MST: $MsiPath" Warning; return $null }

    if (-not $Properties) {
        $Properties = if (Get-Command Get-StandardMstProperties -ErrorAction SilentlyContinue) {
            Get-StandardMstProperties
        } else { @{ ALLUSERS = '1'; REBOOT = 'ReallySuppress' } }
    }
    $mstName = [IO.Path]::GetFileNameWithoutExtension($MsiPath) + '.mst'
    $outMst  = Join-Path $OutputDir $mstName
    try {
        $deferred = Build-Mst -MsiPath $MsiPath -OutputMst $outMst -Properties $Properties -ExistingMst $ExistingMst `
                  -RemoveDesktopShortcut $RemoveDesktopShortcut -RemoveStartupShortcut $RemoveStartupShortcut -RemoveStrayShortcuts $RemoveStrayShortcuts `
                  -RemoveRunKey32 $RemoveRunKey32 -RemoveRunKey64 $RemoveRunKey64 -ApplyExtras $ApplyExtras -AppName $AppName
        if ($null -ne $DeferredRunKeys) { foreach ($x in @($deferred)) { if ($x) { [void]$DeferredRunKeys.Add($x) } } }
        Write-Log "MST created: $outMst (desktop=$RemoveDesktopShortcut startup=$RemoveStartupShortcut stray=$RemoveStrayShortcuts run32=$RemoveRunKey32 run64=$RemoveRunKey64 extras=$(@($ApplyExtras).Count) runKeys->PSADT=$(@($deferred).Count))" Success
        return $outMst
    } catch {
        # An MST integrity failure means a bad transform that would risk an install error - NEVER ship it silently.
        # Propagate so the whole package build fails loudly (a package with a missing/bad .mst is broken either way).
        if ("$($_.Exception.Message)" -match 'integrity check failed') {
            Write-Log "MST build ABORTED (integrity): $($_.Exception.Message)" Error
            throw
        }
        Write-Log "MST build failed: $($_.Exception.Message)" Error; return $null
    }
}

# Inject PSADT post-install Remove-ADTRegistryKey for Run keys the MST couldn't safely delete (they share an MSI
# component with other files/registry, so deleting the row/component would drop the OTHER resources). Removing just the
# VALUE post-install is the only clean way. Writes into the package's Content\Invoke-AppDeployToolkit.ps1 POST-INSTALLATION.
function Add-PsadtRunKeyRemovals {
    param([string]$Ps1Path, [object[]]$RunKeys)
    if (-not $Ps1Path -or -not (Test-Path $Ps1Path) -or -not @($RunKeys).Count) { return 0 }
    $seen = @{}; $lines = New-Object System.Collections.Generic.List[string]
    foreach ($rk in @($RunKeys)) {
        $psKey = "$($rk.PsKey)"; $name = "$($rk.Name)"
        if (-not $psKey.Trim()) { continue }
        $sig = "$psKey|$name"; if ($seen.ContainsKey($sig)) { continue }; $seen[$sig] = $true
        $k = $psKey.Replace("'", "''"); $n = $name.Replace("'", "''")
        [void]$lines.Add("        Remove-ADTRegistryKey -Key '$k' -Name '$n'  # [mst->psadt] Run key shares an MSI component - removed post-install (deleting the component would drop its other resources)")
    }
    if (-not $lines.Count) { return 0 }
    $text = [IO.File]::ReadAllText($Ps1Path)
    # Pick the marker set that matches THIS file: standard #*==== markers, or the GPF "## MARK:" fences after the
    # duplicate-banner strip (Format-OutputScript removes #*==== from GPF output, so a built GPF package is MARK-only).
    $mkset = if (Get-Command Get-PBMarkerSet -ErrorAction SilentlyContinue) { Get-PBMarkerSet -Content $text } else { $script:SectionMarkers }
    $mk = $mkset | Where-Object { $_.F -eq 'PostInstallCode' } | Select-Object -First 1
    if (-not $mk) { return 0 }
    $new = Append-ToSection -Text $text -Begin $mk.B -End $mk.E -Body ($lines -join "`r`n")
    if ($new -ne $text) { [IO.File]::WriteAllText($Ps1Path, $new, (New-Object System.Text.UTF8Encoding $true)); return $lines.Count }
    return 0
}
