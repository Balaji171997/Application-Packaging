##############################################################
# MstBuilder.ps1
# Build (or merge) an MST transform for an MSI via the Windows Installer COM API.
#   - If an existing (vendor) MST is supplied it is applied FIRST, then our
#     standard Property values are merged on top (vendor customisations kept).
#   - Optional removal of desktop shortcuts / Run keys from the MSI tables.
# Ported from the reference tool; logging goes through an injected -Logger
# callback so it stays compatible with this tool's positional Write-Log.
# NOTE: Get-MsiProductCode already lives in Predecessor.ps1 - not redefined here.
##############################################################

# Standard MSI properties from settings.json (DefaultMsiProperties), with ALLUSERS /
# REBOOT always enforced. Returns an ordered hashtable of name -> value.
function Get-StandardMstProperties {
    $props = [ordered]@{}
    $defaults = Get-Setting 'DefaultMsiProperties'
    foreach ($line in @($defaults)) {
        if ("$line" -match '^(.+?)=(.+)$') { $props[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    if (-not $props.Contains('ALLUSERS')) { $props['ALLUSERS'] = '1' }
    if (-not $props.Contains('REBOOT'))   { $props['REBOOT']   = 'ReallySuppress' }
    return $props
}

# Read the Property table of an MSI (read-only) -> ordered list of @{Property;Value}. Used by the
# in-tool property editor so users never need Orca/InstallShield for IAGREE/AGREETOLICENSE-style edits.
function Get-MsiProperties {
    param([Parameter(Mandatory)][string]$MsiPath)
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $MsiPath)) { return $rows }
    $installer = $null; $db = $null; $view = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $db   = $installer.OpenDatabase($MsiPath, 0)   # 0 = read-only
        $view = $db.OpenView('SELECT `Property`, `Value` FROM `Property`')
        $view.Execute($null)
        while ($true) {
            $rec = $view.Fetch(); if (-not $rec) { break }
            $rows.Add([pscustomobject]@{ Property = $rec.StringData(1); Value = $rec.StringData(2) })
            [Runtime.InteropServices.Marshal]::ReleaseComObject($rec) | Out-Null
        }
    } catch { Write-Log "Get-MsiProperties failed for $MsiPath : $($_.Exception.Message)" Warning }
    finally {
        foreach ($o in @($view, $db, $installer)) { if ($o) { try { [Runtime.InteropServices.Marshal]::ReleaseComObject($o) | Out-Null } catch {} } }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
    return ($rows | Sort-Object Property)
}

# Parse a free-text "KEY=VALUE; KEY2=VALUE2" string (; , or newline separated) into a hashtable.
function ConvertTo-MsiPropHashtable {
    param([string]$Text)
    $h = @{}
    if (-not $Text) { return $h }
    foreach ($pair in ($Text -split '[;,\r\n]+')) {
        $p = "$pair".Trim(); if (-not $p) { continue }
        if ($p -match '^([^=]+?)\s*=\s*(.+)$') { $h[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    return $h
}

# PREDECESSOR-REUSE: read what the predecessor's MST actually DID, so the new package replicates it.
# Applies the predecessor MST to its base MSI (in a temp copy) and diffs base-vs-transformed:
#   - desktop Shortcut rows present in base but GONE after transform  -> RemovedShortcut
#   - HKCU/HKLM ...\CurrentVersion\Run registry rows gone (WOW6432Node = 32-bit) -> RemovedRunKey32/64
#   - Property rows added/changed by the transform (minus the always-standard ALLUSERS/REBOOT) -> ExtraProps
# Best-effort + fully guarded: any failure returns $null so it can only PRE-FILL, never block the flow.
# Read matching row keys from a table where a column matches a regex (or all rows). Returns a HashSet of
# the table's primary-key column (col 1). Missing table -> empty set. Plain loop, no nested scriptblocks.
# Returns a List[string] of the table's primary-key (col 1) for rows matching FilterRegex on FilterCol (or
# all rows). Missing table -> empty list. EVERY COM call is voided so no return value pollutes the output;
# OpenView result is null-guarded. Defensive throughout (used for best-effort MST reading).
function Get-MstRowKeys {
    param($Db, [string]$Table, [int]$FilterCol, [string]$FilterRegex)
    $keys = New-Object 'System.Collections.Generic.List[string]'
    if (-not $Db) { return ,$keys }
    $exists = $false
    try { $chk = $Db.OpenView("SELECT * FROM ``$Table``"); if ($chk) { $chk.Execute($null) | Out-Null; $chk.Close() | Out-Null; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($chk); $exists = $true } } catch { $exists = $false }
    if (-not $exists) { return ,$keys }
    try {
        $v = $Db.OpenView("SELECT * FROM ``$Table``")
        if ($v) {
            $v.Execute($null) | Out-Null
            while ($true) {
                $r = $v.Fetch(); if (-not $r) { break }
                $pk = "$($r.StringData(1))"
                $ok = $true
                if ($FilterCol -gt 0) { $ok = ("$($r.StringData($FilterCol))" -match $FilterRegex) }
                if ($ok -and $pk) { [void]$keys.Add($pk) }
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($r)
            }
            $v.Close() | Out-Null; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($v)
        }
    } catch {}
    return ,$keys
}
function Get-MstPropMap {
    param($Db)
    $h = @{}
    if (-not $Db) { return $h }
    try {
        $v = $Db.OpenView('SELECT `Property`,`Value` FROM `Property`')
        if ($v) {
            $v.Execute($null) | Out-Null
            while ($true) { $r = $v.Fetch(); if (-not $r) { break }; $h["$($r.StringData(1))"] = "$($r.StringData(2))"; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($r) }
            $v.Close() | Out-Null; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($v)
        }
    } catch {}
    return $h
}
# Full-row SIGNATURE map for a table: primary-key (col 1) -> all-columns joined with US (char 31). Used to
# diff base-vs-transformed for the report-only "other changes" categories (registry/shortcut/launch cond/etc).
# Missing table -> empty map. Every COM call voided; defensive throughout (best-effort MST reading).
function Get-MstTableSig {
    param($Db, [string]$Table)
    $h = @{}
    if (-not $Db) { return $h }
    # Column count from _Columns (authoritative; Record.FieldCount returns 0 with some installer providers,
    # which would truncate the signature to the PK and silently hide value CHANGES). This also doubles as the
    # table-exists check: a missing table yields 0 columns -> empty map.
    $ncol = 0
    try {
        $cv = $Db.OpenView("SELECT ``Number`` FROM ``_Columns`` WHERE ``Table`` = '$($Table.Replace("'","''"))'")
        if ($cv) {
            $cv.Execute($null) | Out-Null
            while ($true) { $cr = $cv.Fetch(); if (-not $cr) { break }; $ncol++; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($cr) }
            $cv.Close() | Out-Null; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($cv)
        }
    } catch { $ncol = 0 }
    if ($ncol -lt 1) { return $h }
    try {
        $v = $Db.OpenView("SELECT * FROM ``$Table``")
        if ($v) {
            $v.Execute($null) | Out-Null
            while ($true) {
                $r = $v.Fetch(); if (-not $r) { break }
                $pk = "$($r.StringData(1))"
                $parts = New-Object System.Collections.Generic.List[string]
                for ($i = 1; $i -le $ncol; $i++) { try { [void]$parts.Add("$($r.StringData($i))") } catch { break } }
                if ($pk) { $h[$pk] = ($parts -join ([char]31)) }
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($r)
            }
            $v.Close() | Out-Null; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($v)
        }
    } catch {}
    return $h
}
# Export-based table signature: PK (first column) -> all columns joined with US (char 31). Reliable (no StringData).
function Get-MstSigX {
    param($Db, [string]$Table)
    $h = @{}
    foreach ($row in @(Export-MsiTable $Db $Table)) {
        $vals = @(); $pk = $null
        foreach ($p in $row.PSObject.Properties) { if ($null -eq $pk) { $pk = "$($p.Value)" }; $vals += "$($p.Value)" }
        if ($pk) { $h[$pk] = ($vals -join ([char]31)) }
    }
    return $h
}
function Get-MstPropMapX { param($Db) $h=@{}; foreach($row in @(Export-MsiTable $Db 'Property')){ if("$($row.Property)"){ $h["$($row.Property)"]="$($row.Value)" } }; return $h }

# PREDECESSOR REUSE: read what the predecessor's MST actually DID (base vs base+MST), via the reliable Export reader.
# Removed shortcuts are categorised (Desktop/Startup/SendTo/Stray) so each maps to its own toggle; run-key removals
# (row-deleted OR whole-component-removed) are detected; everything else (registry/removefile/launchcondition/feature/
# environment) is offered as opt-in replication (removals) or report-only (adds/changes).
function Read-MstSettings {
    param([Parameter(Mandatory)][string]$MsiPath, [Parameter(Mandatory)][string]$MstPath)
    if (-not (Test-Path $MsiPath) -or -not (Test-Path $MstPath)) { return $null }
    $installer=$null; $dbBase=$null; $dbT=$null; $tmp=$null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $dbBase = $installer.OpenDatabase($MsiPath, 0)
        $tmp = Join-Path (Get-WorkPath 'Temp') ("PkgReadMst_{0}.msi" -f ([Guid]::NewGuid().ToString('N')))
        Copy-Item -LiteralPath $MsiPath -Destination $tmp -Force
        $dbT = $installer.OpenDatabase($tmp, 1)
        [void]$dbT.ApplyTransform($MstPath, 31)   # 31 = suppress transform-validation errors (best-effort); [void] = no pipeline pollution

        # --- Shortcuts the predecessor REMOVED, categorised by folder (Desktop/Startup/SendTo/Stray/Other) ---
        $dirMap=@{}; foreach($d in @(Export-MsiTable $dbBase 'Directory')){ if("$($d.Directory)"){ $dirMap["$($d.Directory)"]=$d } }
        $scBase=@(Export-MsiTable $dbBase 'Shortcut'); $scT=@(Export-MsiTable $dbT 'Shortcut')
        $scTset=@{}; foreach($s in $scT){ $scTset["$($s.Shortcut)"]=$true }
        $cat=@{Desktop=0;Startup=0;SendTo=0;Stray=0;Other=0}
        $scRemOther=New-Object System.Collections.Generic.List[string]   # 'Other' removed shortcuts -> opt-in item (Desktop/Startup/Stray have toggles)
        foreach($s in $scBase){ if($scTset["$($s.Shortcut)"]){ continue }
            $c=Resolve-DirCategory -DirKey "$($s.Directory_)" -DirMap $dirMap; $cat[$c]++
            if($c -eq 'Other'){ [void]$scRemOther.Add("$($s.Shortcut)") } }
        $removedDesktop = $cat.Desktop -gt 0; $removedStartup = $cat.Startup -gt 0; $removedStray = ($cat.SendTo + $cat.Stray) -gt 0

        # --- Run keys the predecessor removed (row deleted OR whole component removed => the reg row is gone) ---
        $regBase=@(Export-MsiTable $dbBase 'Registry'); $regT=@(Export-MsiTable $dbT 'Registry')
        $regTset=@{}; foreach($r in $regT){ $regTset["$($r.Registry)"]=$true }
        $runRemoved=New-Object 'System.Collections.Generic.HashSet[string]'
        foreach($r in $regBase){ if("$($r.Key)" -match '(?i)CurrentVersion\\Run'){ $pk="$($r.Registry)"; if(-not $regTset[$pk]){ [void]$runRemoved.Add($pk) } } }
        $removedRun = $runRemoved.Count -gt 0; $removed32=$removedRun; $removed64=$removedRun

        # --- Properties added/changed (minus the always-standard ALLUSERS/REBOOT) ---
        $pBase=Get-MstPropMapX -Db $dbBase; $pT=Get-MstPropMapX -Db $dbT
        $std=@('ALLUSERS','REBOOT','REBOOTPROMPT'); $extra=[ordered]@{}
        foreach($k in $pT.Keys){ if($std -contains $k){ continue }; if(-not $pBase.ContainsKey($k) -or "$($pBase[$k])" -ne "$($pT[$k])"){ $extra[$k]=$pT[$k] } }

        # --- Other tables (registry beyond run key / other-folder shortcuts / removefile / launch cond / feature / env) ---
        $notes = New-Object System.Collections.Generic.List[string]
        $items = New-Object System.Collections.Generic.List[object]
        $addItem = {
            param($Category,$Action,$Table,$PkCol,$Keys,$CanApply,$Label,$Note)
            $notes.Add($Label) | Out-Null
            $items.Add([pscustomobject]@{ Category=$Category; Action=$Action; Table=$Table; PkCol=$PkCol
                                          Keys=@($Keys); Count=@($Keys).Count; CanApply=[bool]$CanApply; Label=$Label; Note=$Note }) | Out-Null
        }
        try {
            $bReg = Get-MstSigX -Db $dbBase -Table 'Registry'; $tReg = Get-MstSigX -Db $dbT -Table 'Registry'
            $regRem = @($bReg.Keys | Where-Object { -not $tReg.ContainsKey($_) -and -not $runRemoved.Contains($_) })
            $regAdd = @($tReg.Keys | Where-Object { -not $bReg.ContainsKey($_) })
            $regChg = @($bReg.Keys | Where-Object { $tReg.ContainsKey($_) -and $tReg[$_] -ne $bReg[$_] -and -not $runRemoved.Contains($_) })
            if ($regRem.Count) { & $addItem 'Registry' 'remove' 'Registry' 'Registry' $regRem $true "Registry: remove $($regRem.Count) key(s) the predecessor stripped (beyond the Run key)" 'deletes matching registry rows in the new MSI; no-op if absent' }
            if ($regAdd.Count -or $regChg.Count) { & $addItem 'Registry' 'add/change' 'Registry' 'Registry' @() $false "Registry: predecessor ADDED $($regAdd.Count) / CHANGED $($regChg.Count) value(s) - replicate manually (auto-insert could reference a missing component)" 'report-only' }

            $bSc2 = Get-MstSigX -Db $dbBase -Table 'Shortcut'; $tSc2 = Get-MstSigX -Db $dbT -Table 'Shortcut'
            $scRem = @($scRemOther)
            $scChg = @($bSc2.Keys | Where-Object { $tSc2.ContainsKey($_) -and $tSc2[$_] -ne $bSc2[$_] })
            if ($scRem.Count) { & $addItem 'Shortcut' 'remove' 'Shortcut' 'Shortcut' $scRem $true "Shortcuts (other locations): remove $($scRem.Count) the predecessor stripped" 'deletes matching shortcut rows in the new MSI; no-op if absent' }
            if ($scChg.Count) { & $addItem 'Shortcut' 'change' 'Shortcut' 'Shortcut' @() $false "Shortcuts: $($scChg.Count) changed by predecessor - review manually" 'report-only' }

            $bRf = Get-MstSigX -Db $dbBase -Table 'RemoveFile'; $tRf = Get-MstSigX -Db $dbT -Table 'RemoveFile'
            $rfAdd = @($tRf.Keys | Where-Object { -not $bRf.ContainsKey($_) })
            if ($rfAdd.Count) { & $addItem 'RemoveFile' 'add' 'RemoveFile' 'FileKey' @() $false "RemoveFile: predecessor added $($rfAdd.Count) cleanup row(s) - replicate manually" 'report-only' }

            $bLc = Get-MstSigX -Db $dbBase -Table 'LaunchCondition'; $tLc = Get-MstSigX -Db $dbT -Table 'LaunchCondition'
            $lcRem = @($bLc.Keys | Where-Object { -not $tLc.ContainsKey($_) })
            if ($lcRem.Count) { & $addItem 'LaunchCondition' 'remove' 'LaunchCondition' 'Condition' $lcRem $true "LaunchCondition: remove $($lcRem.Count) install check(s) the predecessor bypassed - confirm still appropriate" 'deletes the matching condition in the new MSI; no-op if its text differs' }

            $bFe = Get-MstSigX -Db $dbBase -Table 'Feature'; $tFe = Get-MstSigX -Db $dbT -Table 'Feature'
            $feChg = @($bFe.Keys | Where-Object { $tFe.ContainsKey($_) -and $tFe[$_] -ne $bFe[$_] })
            if ($feChg.Count) { & $addItem 'Feature' 'change' 'Feature' 'Feature' @() $false "Feature: $($feChg.Count) changed in-table by predecessor (often also settable via ADDLOCAL/REMOVE) - review manually" 'report-only' }

            $bEnv = Get-MstSigX -Db $dbBase -Table 'Environment'; $tEnv = Get-MstSigX -Db $dbT -Table 'Environment'
            $envRem = @($bEnv.Keys | Where-Object { -not $tEnv.ContainsKey($_) })
            $envAdd = @($tEnv.Keys | Where-Object { -not $bEnv.ContainsKey($_) })
            $envChg = @($bEnv.Keys | Where-Object { $tEnv.ContainsKey($_) -and $tEnv[$_] -ne $bEnv[$_] })
            if ($envRem.Count) { & $addItem 'Environment' 'remove' 'Environment' 'Environment' $envRem $true "Environment: remove $($envRem.Count) variable(s) the predecessor stripped" 'deletes matching environment rows in the new MSI; no-op if absent' }
            if ($envAdd.Count -or $envChg.Count) { & $addItem 'Environment' 'add/change' 'Environment' 'Environment' @() $false "Environment: predecessor added $($envAdd.Count) / changed $($envChg.Count) - replicate manually" 'report-only' }
        } catch { Write-Log "Read-MstSettings other-changes scan partial: $($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]" Warning }

        $result = @{}
        $result['RemovedShortcut'] = [bool]$removedDesktop     # back-compat alias (= desktop)
        $result['RemovedDesktop']  = [bool]$removedDesktop
        $result['RemovedStartup']  = [bool]$removedStartup
        $result['RemovedStray']    = [bool]$removedStray
        $result['RemovedRunKey32'] = [bool]$removed32
        $result['RemovedRunKey64'] = [bool]$removed64
        $result['ExtraProps']      = $extra
        $result['OtherChanges']    = $notes.ToArray()
        $result['OtherItems']      = $items.ToArray()
        return $result
    } catch { Write-Log "Read-MstSettings failed: $($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]" Warning; return $null }
    finally {
        foreach ($o in @($dbT,$dbBase,$installer)) { if ($o) { try { [Runtime.InteropServices.Marshal]::ReleaseComObject($o)|Out-Null } catch {} } }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Build-Mst {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [Parameter(Mandatory)][string]$OutputMst,
        [Parameter(Mandatory)][hashtable]$Properties,
        [string]$ExistingMst,
        [bool]$RemoveDesktopShortcut = $false,
        [bool]$RemoveStartupShortcut = $false,   # Startup / autostart folder shortcuts
        [bool]$RemoveStrayShortcuts  = $false,   # SendTo / Recent / NetHood / etc.
        [bool]$RemoveRunKey32        = $false,
        [bool]$RemoveRunKey64        = $false,
        [object[]]$ApplyExtras       = @(),     # opt-in predecessor removals (from Read-MstSettings OtherItems)
        [string]$AppName             = '',
        [scriptblock]$Logger         = { param($m) Write-Log $m }
    )
    $tempMsi = Join-Path (Get-WorkPath 'Temp') ("PkgBuilder_{0}.msi" -f ([Guid]::NewGuid().ToString('N')))
    & $Logger "  [MST] copy MSI to temp"
    Copy-Item -LiteralPath $MsiPath -Destination $tempMsi -Force
    # GenerateTransform writes here (a FRESH, writable path); the finished transform is placed at $OutputMst only
    # AFTER the COM databases are released - so a read-only / same-as-vendor target (a vendor MST copied from the
    # read-only live share into Files\ with the MSI's base name) can't lock or block the write.
    $tmpMst = [IO.Path]::ChangeExtension($tempMsi, '.mst')

    $installer = $null; $dbOriginal = $null; $dbModified = $null
    $runDeferred = @()   # Run keys that share a component -> caller removes them via PSADT post-install
    try {
        $installer  = New-Object -ComObject WindowsInstaller.Installer
        $dbOriginal = $installer.OpenDatabase($MsiPath, 0)   # read-only
        $dbModified = $installer.OpenDatabase($tempMsi, 1)   # transacted

        if ($ExistingMst -and (Test-Path $ExistingMst)) {
            & $Logger "  [MST] applying existing/vendor MST"
            $dbModified.ApplyTransform($ExistingMst, 0)
        }

        & $Logger "  [MST] merging $($Properties.Count) standard propert(y/ies)"
        foreach ($key in $Properties.Keys) {
            $k = ([string]$key).Replace("'", "''")
            $v = ([string]$Properties[$key]).Replace("'", "''")
            $viewC = $dbModified.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$k'")
            $viewC.Execute($null); $rec = $viewC.Fetch(); $viewC.Close()
            [Runtime.InteropServices.Marshal]::ReleaseComObject($viewC) | Out-Null
            $sql = if ($rec) {
                [Runtime.InteropServices.Marshal]::ReleaseComObject($rec) | Out-Null
                "UPDATE ``Property`` SET ``Value`` = '$v' WHERE ``Property`` = '$k'"
            } else {
                "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('$k', '$v')"
            }
            $viewW = $dbModified.OpenView($sql); $viewW.Execute($null); $viewW.Close()
            [Runtime.InteropServices.Marshal]::ReleaseComObject($viewW) | Out-Null
        }

        if ($RemoveDesktopShortcut -or $RemoveStartupShortcut -or $RemoveStrayShortcuts -or $RemoveRunKey32 -or $RemoveRunKey64) {
            # Reliable cleanup: Export-based reader decides, delete-by-PK applies. Run keys use the keypath-aware rule
            # (dedicated -> remove whole component; shared non-keypath -> delete row; shared keypath -> reassign+delete
            # or PSADT). Shortcuts are categorised (Desktop/Startup/SendTo/Stray) by resolving the Directory tree.
            & $Logger "  [MST] planning cleanup (Export-based reader): run keys + shortcuts"
            $plan = Get-MsiCleanupPlan -Db $dbModified -RemoveRun32 $RemoveRunKey32 -RemoveRun64 $RemoveRunKey64 `
                        -RemoveDesktop $RemoveDesktopShortcut -RemoveStartup $RemoveStartupShortcut -RemoveStray $RemoveStrayShortcuts -Logger $Logger
            foreach ($ln in @($plan.Report)) { & $Logger "  [MST] $ln" }
            Invoke-MsiCleanupPlan -Db $dbModified -Plan $plan -Logger $Logger
            $runDeferred = @($plan.DeferPsadt)
            if ($runDeferred.Count) { & $Logger "  [MST] $($runDeferred.Count) Run key(s) -> removed via PSADT post-install (shared-component keypath, no reassign target)" }
        }

        # User-confirmed predecessor removals (LaunchCondition / non-desktop shortcut / extra registry key /
        # environment). Each deletes rows whose primary key matches what the predecessor stripped - a safe
        # no-op when the new MSI no longer has that key, so it can never corrupt the package.
        foreach ($x in @($ApplyExtras)) {
            if (-not $x) { continue }
            if ("$($x.Action)" -ne 'remove') { continue }
            $tbl = "$($x.Table)"; $pkCol = "$($x.PkCol)"; $keys = @($x.Keys)
            if (-not $tbl -or -not $pkCol -or -not $keys.Count) { continue }
            & $Logger "  [MST] replicating predecessor removal in $tbl ($($keys.Count) key(s))"
            [void](Remove-MsiRowsByPk -Db $dbModified -Table $tbl -PkCol $pkCol -Pks $keys -Logger $Logger)   # reliable delete-by-PK
        }

        $dbModified.Commit() | Out-Null
        if (Test-Path $tmpMst) { try { Set-ItemProperty -LiteralPath $tmpMst -Name IsReadOnly -Value $false -EA SilentlyContinue } catch {}; Remove-Item -LiteralPath $tmpMst -Force -EA SilentlyContinue }
        $dbModified.GenerateTransform($dbOriginal, $tmpMst) | Out-Null
        if (-not (Test-Path $tmpMst)) {
            # No differences yet (the MSI already matched every standard property and there was nothing to remove):
            # inject a benign packaging marker so a VALID transform is always produced - the install command always
            # references this .mst, so it must exist.
            & $Logger "  [MST] no differences - adding packaging marker so a valid transform is produced"
            $vwM = $dbModified.OpenView("INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('MTBTRANSFORM', '1')")
            $vwM.Execute($null); $vwM.Close(); [Runtime.InteropServices.Marshal]::ReleaseComObject($vwM) | Out-Null
            $dbModified.Commit() | Out-Null
            $dbModified.GenerateTransform($dbOriginal, $tmpMst) | Out-Null
        }
        $dbModified.CreateTransformSummaryInfo($dbOriginal, $tmpMst, 0, 0) | Out-Null
    } finally {
        foreach ($o in @($dbModified, $dbOriginal, $installer)) {
            if ($o) { [Runtime.InteropServices.Marshal]::ReleaseComObject($o) | Out-Null }
        }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        if (Test-Path $tempMsi) { Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue }
    }
    # COM is released - now place the finished transform at $OutputMst (clear a read-only / stale target first, e.g.
    # a vendor MST copied from the read-only live share with the same base name). Done outside the try so the
    # databases no longer hold a handle to the file.
    if (Test-Path $tmpMst) {
        $od = Split-Path -Parent $OutputMst
        if ($od -and -not (Test-Path $od)) { New-Item $od -ItemType Directory -Force | Out-Null }
        try { if (Test-Path $OutputMst) { Set-ItemProperty -LiteralPath $OutputMst -Name IsReadOnly -Value $false -EA SilentlyContinue; Remove-Item -LiteralPath $OutputMst -Force -EA SilentlyContinue } } catch {}
        Copy-Item -LiteralPath $tmpMst -Destination $OutputMst -Force
        Remove-Item -LiteralPath $tmpMst -Force -ErrorAction SilentlyContinue
        & $Logger "  [MST] done -> $OutputMst"
    } else {
        throw "GenerateTransform produced no transform file."
    }
    # VALIDATION GATE: apply the finished MST to a copy of the base MSI and verify it can't cause an install-time error
    # (dangling KeyPath / orphaned component reference). A failure here means a bug produced an unsafe MST -> refuse it.
    if (Test-Path $OutputMst) {
        $issues = @(Test-MstIntegrity -MsiPath $MsiPath -MstPath $OutputMst -Logger $Logger)
        if ($issues.Count) {
            foreach ($i in $issues) { & $Logger "  [MST] !! INTEGRITY: $i" }
            throw "MST integrity check failed for $([IO.Path]::GetFileName($MsiPath)) - refusing to ship (would risk an install error): $($issues -join '; ')"
        }
        & $Logger "  [MST] integrity OK - no dangling keypath / orphaned component references"
    }
    return ,@($runDeferred)   # Run keys the caller must remove via PSADT post-install (comma keeps an empty/1-item array intact)
}

# =====================================================================================================================
# RELIABLE MSI CLEANUP (Run keys + shortcuts). The old OpenView/Fetch/StringData reader returned rows NON-
# DETERMINISTICALLY on real MSIs (missing/blank rows), which mis-counted component footprints. We now READ via
# Database.Export (deterministic IDT serialization) and DELETE by exact primary key (server-side WHERE match).
# =====================================================================================================================

# Export one MSI table to a temp .idt and parse it into ordered PSObjects keyed by column name. Deterministic.
function Export-MsiTable {
    param($Db, [string]$Table)
    $rows = New-Object System.Collections.Generic.List[object]
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('mstx_' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item $dir -ItemType Directory -Force | Out-Null
        try { $Db.Export($Table, $dir, "$Table.idt") } catch { return $rows }   # table absent -> empty
        $idtPath = Join-Path $dir "$Table.idt"
        if (-not (Test-Path $idtPath)) { return $rows }
        $lines = @([IO.File]::ReadAllLines($idtPath))
        if ($lines.Count -lt 4) { return $rows }                                # 3 header lines + >=1 data row
        $cols = $lines[0] -split "`t"
        for ($li = 3; $li -lt $lines.Count; $li++) {
            if ($lines[$li] -eq '') { continue }
            $f = $lines[$li] -split "`t"
            $h = [ordered]@{}
            for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = $(if ($i -lt $f.Count) { $f[$i] } else { '' }) }
            $rows.Add([pscustomobject]$h)
        }
    } catch {} finally { if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue } }
    return $rows
}

# Classify a shortcut's Directory_ by walking the Directory parent chain and matching known system-folder tokens.
# Returns Desktop / Startup / SendTo / Stray / Other(keep). Robust to WiX custom dirs (e.g. WIX_DIR_COMMON_ALTSTARTUP).
function Resolve-DirCategory {
    param([string]$DirKey, [hashtable]$DirMap)
    $tokens = ''; $k = "$DirKey"; $seen = @{}
    while ($k -and -not $seen[$k]) {
        $seen[$k] = $true; $tokens += " $k"
        $d = $DirMap[$k]; if (-not $d) { break }
        $tokens += " $($d.DefaultDir)"; $k = "$($d.Directory_Parent)"
    }
    $t = $tokens.ToLower()
    if ($t -match 'desktop')                                             { return 'Desktop' }
    if ($t -match 'startupfolder|altstartup|\bstartup\b')                { return 'Startup' }
    if ($t -match 'sendto')                                              { return 'SendTo' }
    if ($t -match 'recent|nethood|printhood|template|favorite|quicklaunch') { return 'Stray' }
    return 'Other'   # ProgramMenu / StartMenu / install dirs -> KEEP (real app shortcuts)
}

# PURE cleanup planner (unit-tested). Given the exported tables + toggles, decide exactly what to change. No COM.
#   RunKey rules:  dedicated component (only the run key)        -> remove the WHOLE component
#                  shared, run row is NOT the component KeyPath  -> delete just the registry row
#                  shared, run row IS the KeyPath                -> reassign KeyPath to a file/other reg, then delete row
#                                                                   (no target -> keep row, remove via PSADT post-install)
function Resolve-MsiCleanupPlan {
    param([object[]]$Registry, [object[]]$File, [object[]]$Shortcut, [object[]]$Directory, [object[]]$Component,
          [bool]$RemoveRun32, [bool]$RemoveRun64, [bool]$RemoveDesktop, [bool]$RemoveStartup, [bool]$RemoveStray)
    $plan = @{ RemoveComponents=(New-Object System.Collections.Generic.List[string]); DeleteRegistry=(New-Object System.Collections.Generic.List[string])
               DeleteShortcuts=(New-Object System.Collections.Generic.List[string]); ReKeyPath=(New-Object System.Collections.Generic.List[object])
               DeferPsadt=(New-Object System.Collections.Generic.List[object]); Report=(New-Object System.Collections.Generic.List[string]) }
    $compMap=@{}; foreach($c in @($Component)){ if("$($c.Component)"){ $compMap["$($c.Component)"]=$c } }
    $dirMap =@{}; foreach($d in @($Directory)){ if("$($d.Directory)"){ $dirMap["$($d.Directory)"]=$d } }
    $regByComp=@{}; foreach($r in @($Registry)){ $c="$($r.Component_)"; if($c){ if(-not $regByComp[$c]){$regByComp[$c]=New-Object System.Collections.Generic.List[object]}; $regByComp[$c].Add($r) } }
    $fileByComp=@{}; foreach($f in @($File)){ $c="$($f.Component_)"; if($c){ $fileByComp[$c]=1+[int]$fileByComp[$c] } }
    $scByComp =@{}; foreach($s in @($Shortcut)){ $c="$($s.Component_)"; if($c){ $scByComp[$c]=1+[int]$scByComp[$c] } }
    $rootMap=@{ '-1'='HKLM';'0'='HKCR';'1'='HKCU';'2'='HKLM';'3'='HKU' }

    # --- RUN KEYS ---
    if ($RemoveRun32 -or $RemoveRun64) {
        foreach($r in @($Registry)){
            $key="$($r.Key)"; if($key -inotmatch 'CurrentVersion\\Run'){ continue }
            $is32 = $key -imatch 'WOW6432Node'
            $want = ($is32 -and $RemoveRun32) -or ((-not $is32) -and $RemoveRun64)
            if(-not $want){ continue }
            $c="$($r.Component_)"; $cObj=$compMap[$c]
            $otherReg = ([int]$regByComp[$c].Count) - 1     # .Count direct: @() on a List[object] of PSObjects throws in PS 5.1
            $hasOther = ($otherReg -gt 0) -or ([int]$fileByComp[$c] -gt 0) -or ([int]$scByComp[$c] -gt 0)
            $attr = [int]("0" + "$($cObj.Attributes)")
            $isKeyPath = (($attr -band 4) -ne 0) -and ("$($cObj.KeyPath)" -eq "$($r.Registry)")
            if(-not $hasOther){
                if($plan.RemoveComponents -notcontains $c){ [void]$plan.RemoveComponents.Add($c) }
                [void]$plan.Report.Add("Run key '$($r.Name)': component '$c' is dedicated to it -> remove the whole component (row+component+feature refs)")
            } elseif(-not $isKeyPath){
                [void]$plan.DeleteRegistry.Add("$($r.Registry)")
                [void]$plan.Report.Add("Run key '$($r.Name)': shared component '$c', not its keypath -> delete just the registry row")
            } else {
                $target=$null; $newAttr=$attr
                $f2=@($File | Where-Object { "$($_.Component_)" -eq $c } | Select-Object -First 1)
                if($f2.Count){ $target="$($f2[0].File)"; $newAttr = ($attr -band (-bnot 4)) }              # file keypath -> clear reg-keypath bit
                else { $r2=@($regByComp[$c] | Where-Object { "$($_.Registry)" -ne "$($r.Registry)" } | Select-Object -First 1)
                       if($r2.Count){ $target="$($r2[0].Registry)"; $newAttr=$attr } }                     # another registry keypath, keep bit 4
                if($target){
                    [void]$plan.ReKeyPath.Add([pscustomobject]@{ Component=$c; NewKeyPath=$target; NewAttributes=$newAttr })
                    [void]$plan.DeleteRegistry.Add("$($r.Registry)")
                    [void]$plan.Report.Add("Run key '$($r.Name)': is the keypath of shared component '$c' -> reassign keypath to '$target', then delete the row")
                } else {
                    $hive=$rootMap["$($r.Root)"]; if(-not $hive){$hive='HKLM'}
                    [void]$plan.DeferPsadt.Add([pscustomobject]@{ Root="$($r.Root)"; Key=$key; Name="$($r.Name)"; Value="$($r.Value)"; Component=$c; PsKey="${hive}:\$key" })
                    [void]$plan.Report.Add("Run key '$($r.Name)': keypath of '$c' with no reassignment target -> remove via PSADT post-install")
                }
            }
        }
    }
    # --- SHORTCUTS (Desktop / Startup / SendTo / Stray). Shortcuts are NEVER a component keypath -> always safe to delete the row.
    if ($RemoveDesktop -or $RemoveStartup -or $RemoveStray) {
        foreach($s in @($Shortcut)){
            if(-not "$($s.Shortcut)"){ continue }
            $cat = Resolve-DirCategory -DirKey "$($s.Directory_)" -DirMap $dirMap
            $take = ($cat -eq 'Desktop' -and $RemoveDesktop) -or ($cat -eq 'Startup' -and $RemoveStartup) -or (($cat -eq 'SendTo' -or $cat -eq 'Stray') -and $RemoveStray)
            if($take){ [void]$plan.DeleteShortcuts.Add("$($s.Shortcut)"); [void]$plan.Report.Add("Shortcut '$($s.Name)' in $cat folder -> remove") }
        }
    }
    # Return plain ARRAYS (not List[object]) so downstream @()/foreach can't hit the PS 5.1 List-wrap bug.
    return @{ RemoveComponents=$plan.RemoveComponents.ToArray(); DeleteRegistry=$plan.DeleteRegistry.ToArray()
              DeleteShortcuts=$plan.DeleteShortcuts.ToArray(); ReKeyPath=$plan.ReKeyPath.ToArray()
              DeferPsadt=$plan.DeferPsadt.ToArray(); Report=$plan.Report.ToArray() }
}

# IO wrapper: Export the tables via the reliable reader, then run the pure planner.
function Get-MsiCleanupPlan {
    param($Db, [bool]$RemoveRun32, [bool]$RemoveRun64, [bool]$RemoveDesktop, [bool]$RemoveStartup, [bool]$RemoveStray, [scriptblock]$Logger = { param($m) })
    $reg=@(Export-MsiTable $Db 'Registry'); $file=@(Export-MsiTable $Db 'File'); $sc=@(Export-MsiTable $Db 'Shortcut')
    $dir=@(Export-MsiTable $Db 'Directory'); $comp=@(Export-MsiTable $Db 'Component')
    return (Resolve-MsiCleanupPlan -Registry $reg -File $file -Shortcut $sc -Directory $dir -Component $comp `
              -RemoveRun32 $RemoveRun32 -RemoveRun64 $RemoveRun64 -RemoveDesktop $RemoveDesktop -RemoveStartup $RemoveStartup -RemoveStray $RemoveStray)
}

# Reliable delete: for each key value, delete EVERY row matching WHERE PkCol = value (server-side match, no StringData).
# Works for true PKs (one row) and for referencing columns like Component_ (all matching rows).
function Remove-MsiRowsByPk {
    param($Db, [string]$Table, [string]$PkCol, [string[]]$Pks, [scriptblock]$Logger = { param($m) })
    try { $chk=$Db.OpenView("SELECT * FROM ``$Table``"); $chk.Execute($null); $chk.Close(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($chk) }
    catch { & $Logger "    (table $Table not present - skip)"; return 0 }
    $removed=0
    foreach($pk in @($Pks | Select-Object -Unique)){
        if($null -eq $pk -or "$pk" -eq ''){ continue }
        $pv="$pk".Replace("'","''")
        do {
            $rec=$null
            try {
                $v=$Db.OpenView("SELECT * FROM ``$Table`` WHERE ``$PkCol`` = '$pv'"); $v.Execute($null); $rec=$v.Fetch()
                if($rec){ $v.Modify(6, $rec); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($rec); $removed++ }
                $v.Close(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($v)
            } catch { & $Logger "    delete failed $Table[$PkCol='$pv']: $($_.Exception.Message)"; $rec=$null }
        } while ($rec)
    }
    if($removed){ & $Logger "    removed $removed row(s) from $Table" }
    return $removed
}

# Reassign a component's KeyPath (used when a shared component's run key IS the keypath).
function Set-MsiComponentKeyPath {
    param($Db, [string]$Component, [string]$NewKeyPath, [int]$NewAttributes, [scriptblock]$Logger = { param($m) })
    $cv="$Component".Replace("'","''"); $kp="$NewKeyPath".Replace("'","''")
    try {
        $v=$Db.OpenView("UPDATE ``Component`` SET ``KeyPath`` = '$kp', ``Attributes`` = $NewAttributes WHERE ``Component`` = '$cv'")
        $v.Execute($null); $v.Close(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($v)
        & $Logger "    reassigned KeyPath of '$Component' -> '$NewKeyPath' (attr $NewAttributes)"
    } catch { & $Logger "    keypath reassign failed for '$Component': $($_.Exception.Message)" }
}

# Apply the cleanup plan to a (transacted) database. Order: reassign keypaths -> delete rows -> remove whole components.
function Invoke-MsiCleanupPlan {
    param($Db, $Plan, [scriptblock]$Logger = { param($m) })
    foreach($k in @($Plan.ReKeyPath)){ Set-MsiComponentKeyPath -Db $Db -Component "$($k.Component)" -NewKeyPath "$($k.NewKeyPath)" -NewAttributes ([int]$k.NewAttributes) -Logger $Logger }
    if(@($Plan.DeleteRegistry).Count){ [void](Remove-MsiRowsByPk -Db $Db -Table 'Registry' -PkCol 'Registry' -Pks @($Plan.DeleteRegistry) -Logger $Logger) }
    if(@($Plan.DeleteShortcuts).Count){ [void](Remove-MsiRowsByPk -Db $Db -Table 'Shortcut' -PkCol 'Shortcut' -Pks @($Plan.DeleteShortcuts) -Logger $Logger) }
    foreach($c in @($Plan.RemoveComponents | Select-Object -Unique)){
        [void](Remove-MsiRowsByPk -Db $Db -Table 'Registry'          -PkCol 'Component_' -Pks @($c) -Logger $Logger)
        [void](Remove-MsiRowsByPk -Db $Db -Table 'Shortcut'          -PkCol 'Component_' -Pks @($c) -Logger $Logger)
        [void](Remove-MsiRowsByPk -Db $Db -Table 'File'              -PkCol 'Component_' -Pks @($c) -Logger $Logger)
        [void](Remove-MsiRowsByPk -Db $Db -Table 'FeatureComponents' -PkCol 'Component_' -Pks @($c) -Logger $Logger)
        [void](Remove-MsiRowsByPk -Db $Db -Table 'Component'         -PkCol 'Component'  -Pks @($c) -Logger $Logger)
        & $Logger "  [MST] removed dedicated component '$c' (registry/shortcut/file/featurecomponents/component)"
    }
}

# VALIDATION GATE: apply the finished MST to a copy and check for the two states that cause install-time MSI errors:
# a dangling KeyPath, or an orphaned reference to a removed component. Returns a list of issues ([] = clean).
function Test-MstIntegrity {
    param([string]$MsiPath, [string]$MstPath, [scriptblock]$Logger = { param($m) })
    $issues = New-Object System.Collections.Generic.List[string]
    $installer=$null; $db=$null
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('mstchk_'+[Guid]::NewGuid().ToString('N')+'.msi')
    try {
        Copy-Item -LiteralPath $MsiPath -Destination $tmp -Force
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $db = $installer.OpenDatabase($tmp, 1)
        try { [void]$db.ApplyTransform($MstPath, 0) } catch { [void]$issues.Add("transform did not apply cleanly: $($_.Exception.Message)"); return $issues.ToArray() }
        $reg=@(Export-MsiTable $db 'Registry'); $file=@(Export-MsiTable $db 'File'); $comp=@(Export-MsiTable $db 'Component')
        $sc=@(Export-MsiTable $db 'Shortcut'); $fc=@(Export-MsiTable $db 'FeatureComponents')
        $compSet=@{}; foreach($c in $comp){ $compSet["$($c.Component)"]=$true }
        $regSet=@{};  foreach($r in $reg){ $regSet["$($r.Registry)"]=$true }
        $fileSet=@{}; foreach($f in $file){ $fileSet["$($f.File)"]=$true }
        foreach($c in $comp){
            $attr=[int]("0"+"$($c.Attributes)"); $kp="$($c.KeyPath)"; if(-not $kp){ continue }
            if(($attr -band 4) -ne 0){ if(-not $regSet[$kp]){ [void]$issues.Add("component '$($c.Component)' keypath -> missing registry row '$kp'") } }
            else { if(-not $fileSet[$kp]){ [void]$issues.Add("component '$($c.Component)' keypath -> missing file '$kp'") } }
        }
        foreach($r in $reg){ if("$($r.Component_)" -and -not $compSet["$($r.Component_)"]){ [void]$issues.Add("registry '$($r.Registry)' -> missing component '$($r.Component_)'") } }
        foreach($s in $sc){ if("$($s.Component_)" -and -not $compSet["$($s.Component_)"]){ [void]$issues.Add("shortcut '$($s.Shortcut)' -> missing component '$($s.Component_)'") } }
        foreach($f in $file){ if("$($f.Component_)" -and -not $compSet["$($f.Component_)"]){ [void]$issues.Add("file '$($f.File)' -> missing component '$($f.Component_)'") } }
        foreach($x in $fc){ if("$($x.Component_)" -and -not $compSet["$($x.Component_)"]){ [void]$issues.Add("featurecomponents -> missing component '$($x.Component_)'") } }
    } catch { [void]$issues.Add("integrity check error: $($_.Exception.Message)") }
    finally {
        foreach($o in @($db,$installer)){ if($o){ try{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)}catch{} } }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        if(Test-Path $tmp){ Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
    return $issues.ToArray()   # return the string ELEMENTS (not the List object) so the caller's @() gets real issues only
}

# Delete rows from an MSI table matching a PS RowFilter (MSI SQL has no DELETE WHERE / LIKE).
function Remove-MsiTableRows {
    param($Db, [string]$Table, [scriptblock]$RowFilter, [string[]]$Columns, [scriptblock]$Logger)
    try {
        $check = $Db.OpenView("SELECT * FROM ``$Table``"); $check.Execute($null); $check.Close()
        [Runtime.InteropServices.Marshal]::ReleaseComObject($check) | Out-Null
    } catch { & $Logger "    (table $Table not present - skip)"; return }

    $colList = ($Columns | ForEach-Object { "``$_``" }) -join ', '
    $removed = 0
    try {
        $view = $Db.OpenView("SELECT $colList FROM ``$Table``"); $view.Execute($null)
        $records = New-Object System.Collections.Generic.List[object]
        while ($true) {
            $rec = $view.Fetch(); if (-not $rec) { break }
            $colDict = @{}
            for ($i = 0; $i -lt $Columns.Count; $i++) { $colDict[$Columns[$i]] = $rec.StringData($i + 1) }
            if (& $RowFilter $colDict) { $records.Add($rec) }
            else { [Runtime.InteropServices.Marshal]::ReleaseComObject($rec) | Out-Null }
        }
        $view.Close(); [Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null
        if ($records.Count -eq 0) { & $Logger "    (no matching rows in $Table)"; return }

        $pkCol = $Columns[0]
        foreach ($r in $records) {
            $pkVal = $r.StringData(1).Replace("'", "''")
            try {
                $delView = $Db.OpenView("SELECT * FROM ``$Table`` WHERE ``$pkCol`` = '$pkVal'")
                $delView.Execute($null); $delRec = $delView.Fetch()
                if ($delRec) {
                    $delView.Modify(6, $delRec)   # 6 = msiViewModifyDelete
                    [Runtime.InteropServices.Marshal]::ReleaseComObject($delRec) | Out-Null
                    $removed++
                }
                $delView.Close(); [Runtime.InteropServices.Marshal]::ReleaseComObject($delView) | Out-Null
            } catch { & $Logger "    delete failed for $Table '$pkVal': $($_.Exception.Message)" }
            [Runtime.InteropServices.Marshal]::ReleaseComObject($r) | Out-Null
        }
        & $Logger "    removed $removed row(s) from $Table"
    } catch { & $Logger "    $Table edit failed: $($_.Exception.Message)" }
}
