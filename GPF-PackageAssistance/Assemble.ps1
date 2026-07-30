##############################################################
# Assemble.ps1  -  Step 4: turn the assembled script + resolved source into a
# real PSADT v4 package folder on disk. The Invoke-AppDeployToolkit.ps1 is ALREADY
# built/edited in Step 3 (ScriptText); here we only lay down files:
#   1. copy the blank template (Content/ + Documents/ + Icons/) to <Output>\<FullName>
#   2. write the Step-3 script over Content\Invoke-AppDeployToolkit.ps1
#   3. source -> Content\Files\  (installers + payload, OR a single zip for loose files)
#   4. docs -> Documents\, icons -> Icons\
#   5. ARP icon -> Content\SupportFiles\Icon.ico (when an ARP entry was requested)
#   6. MST for an MSI (vendor MST merged + Step-2 checkbox flags)
#   7. unblock everything (strip Zone.Identifier)
##############################################################

function Ensure-Dir { param([string]$p) if ($p -and -not (Test-Path $p)) { New-Item $p -ItemType Directory -Force | Out-Null } }

# Locate the blank template ROOT (the folder that holds Content\ + Documents\ + Icons\).
# Prefer an extracted PSADT_Template\ folder; else extract PSADT_Template.zip to a temp dir.
function Get-TemplateRoot {
    param([string]$Root)
    if (-not $Root) { $Root = if ($PSScriptRoot) { $PSScriptRoot } else { Get-ToolRoot } }
    # Brand template folder first (e.g. PSADT_Template_GPF); default MTB = PSADT_Template.
    $tplName = if (Get-Command Get-PBBrand -ErrorAction SilentlyContinue) { Get-PBBrand -Path 'TemplateRoot' -Default 'PSADT_Template' } else { 'PSADT_Template' }
    foreach ($cand in @((Join-Path $Root $tplName), (Join-Path $Root "Lib\$tplName"),
                        (Join-Path $Root 'PSADT_Template'), (Join-Path $Root 'Lib\PSADT_Template'))) {
        if (Test-Path (Join-Path $cand 'Content\Invoke-AppDeployToolkit.ps1')) { return @{ Path = $cand; Temp = $null } }
    }
    $zip = Join-Path $Root 'PSADT_Template.zip'
    if (-not (Test-Path $zip)) { $zip = Join-Path $Root 'Lib\PSADT_Template.zip' }
    if (Test-Path $zip) {
        $tmp = Join-Path (Get-WorkPath 'Temp') "PBtplroot_$(Get-Random)"
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $inner = Get-ChildItem $tmp -Directory -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { Test-Path (Join-Path $_.FullName 'Content\Invoke-AppDeployToolkit.ps1') } | Select-Object -First 1
        if ($inner) { return @{ Path = $inner.FullName; Temp = $tmp } }
        return @{ Path = $tmp; Temp = $tmp }
    }
    return @{ Path = $null; Temp = $null }
}

# Build Files\<FullName>.zip for a loose-files package. If the payload is a single .zip,
# reuse it (renamed); otherwise stage every non-doc/non-icon file (structure preserved)
# and compress. Returns the zip path or $null.
function New-PayloadZip {
    param([object[]]$PayloadFiles, [string]$SrcRoot, [string]$DestZip)
    $files = @($PayloadFiles | Where-Object { $_ })
    $zips  = @($files | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.zip' })
    if ($zips.Count -eq 1 -and $files.Count -eq 1) {
        Copy-Item -LiteralPath $zips[0].FullName -Destination $DestZip -Force
        return $DestZip
    }
    if (-not $SrcRoot -or -not (Test-Path $SrcRoot)) { return $null }
    $stage = Join-Path (Get-WorkPath 'Temp') "PBzip_$(Get-Random)"
    Ensure-Dir $stage
    try {
        foreach ($f in @(Get-ChildItem -LiteralPath $SrcRoot -File -Recurse -ErrorAction SilentlyContinue)) {
            if ((Get-FileClass $f.FullName) -in @('Document','Icon')) { continue }
            $rel = $f.FullName.Substring($SrcRoot.Length).TrimStart('\','/')
            $tgt = Join-Path $stage $rel
            Ensure-Dir (Split-Path $tgt -Parent)
            Copy-Item -LiteralPath $f.FullName -Destination $tgt -Force
        }
        if (Test-Path $DestZip) { Remove-Item $DestZip -Force }
        Compress-Archive -Path "$stage\*" -DestinationPath $DestZip -Force
        return $DestZip
    } finally { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

# Common parent directory of a set of files (for loose payload root).
function Get-CommonParent {
    param([object[]]$Files)
    $dirs = @($Files | Where-Object { $_ } | ForEach-Object { Split-Path -Parent $_.FullName } | Select-Object -Unique)
    if ($dirs.Count -eq 0) { return $null }
    if ($dirs.Count -eq 1) { return $dirs[0] }
    $parts = ($dirs[0] -split '[\\/]')
    for ($i = $parts.Count; $i -ge 1; $i--) {
        $prefix = ($parts[0..($i-1)] -join '\')
        if (@($dirs | Where-Object { $_ -notlike "$prefix*" }).Count -eq 0) { return $prefix }
    }
    return (Split-Path -Parent $dirs[0])
}

# Convert an .ico to a .png (medium quality: closest frame to 256, longest side capped at 256).
function Convert-IcoToPng {
    param([string]$IcoPath, [string]$PngPath)
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $icon = New-Object System.Drawing.Icon($IcoPath, 256, 256)
        $bmp  = $icon.ToBitmap()
        $max  = [Math]::Max($bmp.Width, $bmp.Height)
        if ($max -gt 256) {
            $scale = 256 / $max
            $nb = New-Object System.Drawing.Bitmap([int]($bmp.Width * $scale), [int]($bmp.Height * $scale))
            $g  = [System.Drawing.Graphics]::FromImage($nb)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($bmp, 0, 0, $nb.Width, $nb.Height); $g.Dispose(); $bmp.Dispose(); $bmp = $nb
        }
        $bmp.Save($PngPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose(); $icon.Dispose(); return $true
    } catch { Write-Log "ico->png failed for $([IO.Path]::GetFileName($IcoPath)): $($_.Exception.Message)" Warning; return $false }
}

# Populate the package Icons\ folder: copy .ico/.png from the source Icons folder; for any
# .ico without a sibling .png, generate the .png; if still empty, extract from an EXE in Files\.
function Copy-PackageIcons {
    param([hashtable]$Resolved, [string]$IconsDir, [string]$FilesDir)
    Ensure-Dir $IconsDir
    $src = $null
    if ($Resolved -and $Resolved.IconsPath -and (Test-Path $Resolved.IconsPath)) { $src = $Resolved.IconsPath }
    elseif ($Resolved -and $Resolved.RootPath -and (Test-Path $Resolved.RootPath)) {
        $src = Find-FolderByNames -Root $Resolved.RootPath -Names $script:IconNames -MaxDepth 7
        if (-not $src -and (Get-Command Get-PackageRootFolder -EA SilentlyContinue)) {
            # search WITHIN the package root only - never climb into a multi-package share (cross-package contamination).
            $pkgRoot = Get-PackageRootFolder -Path $Resolved.RootPath
            if ($pkgRoot -and $pkgRoot -ne $Resolved.RootPath) { $src = Find-FolderByNames -Root $pkgRoot -Names $script:IconNames -MaxDepth 4 }
        }
    }
    if ($src -and (Test-Path $src)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension.ToLower() -in '.ico','.png' })) {
            Copy-Item -LiteralPath $f.FullName -Destination $IconsDir -Force
        }
        Write-Log "Icons copied from $src" Success
    }
    # The .ico and the .png MUST be the SAME image (user rule): the .ico drives the ARP/SCCM icon and the .png drives
    # Intune - a mismatched pair shows two different icons for one app. Whenever an .ico exists, guarantee a .png with
    # the SAME BASENAME generated FROM that .ico (even if some other .png is already lying in the folder - Intune then
    # prefers the matched pair). Predecessor reuse with an ico-only Icons folder gets its png generated here too.
    $ico = Get-ChildItem -LiteralPath $IconsDir -File -Filter *.ico -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ico) {
        $png = Join-Path $IconsDir ($ico.BaseName + '.png')
        if (-not (Test-Path -LiteralPath $png)) {
            if (Convert-IcoToPng -IcoPath $ico.FullName -PngPath $png) { Write-Log "Generated $($ico.BaseName).png from $($ico.Name) (matched ico/png pair)" Success }
        }
    }
    # still empty -> extract from an EXE in Files\ (and make its png too)
    if (-not (Get-ChildItem -LiteralPath $IconsDir -File -ErrorAction SilentlyContinue)) {
        $exe = Get-ChildItem -LiteralPath $FilesDir -File -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) {
            try {
                Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
                $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($exe.FullName)
                if ($ic) {
                    $dest = Join-Path $IconsDir ($exe.BaseName + '.ico')
                    $fs = [IO.File]::Open($dest, 'Create'); try { $ic.Save($fs) } finally { $fs.Close(); $ic.Dispose() }
                    Convert-IcoToPng -IcoPath $dest -PngPath (Join-Path $IconsDir ($exe.BaseName + '.png')) | Out-Null
                    Write-Log "Icon extracted from $($exe.Name) -> Icons\" Success
                }
            } catch { Write-Log "Icon extraction failed: $($_.Exception.Message)" Warning }
        }
    }
}

# PREDECESSOR REUSE: carry forward the packager-authored Active Setup .ps1 file(s). These live ONLY in the
# predecessor package's SupportFiles (they are NOT vendor-source files), so a reuse build that references
# "SupportFiles\<App>_<newver>_ActiveSetup_Install.ps1" would otherwise ship a BROKEN reference. We copy each one,
# version-swap its FILENAME and its CONTENT (pred->new, plus the same pred-of-pred bump the script gets), so the
# carried stub matches the version the reused script now calls. Returns the number of files carried.
function Copy-PredecessorActiveSetup {
    param([string]$PredecessorPath, [string]$SupportDir, [hashtable]$NewPkg, [string]$PredVersion)
    if (-not $PredecessorPath -or -not (Test-Path $PredecessorPath)) { return 0 }
    $newVer = "$($NewPkg.Version)"
    if (-not $PredVersion -or -not $newVer) { return 0 }
    # Predecessor SupportFiles: <pkg>\Content\SupportFiles (v4) or <pkg>\SupportFiles (v3) - take whichever exists.
    $predSupport = @("$PredecessorPath\Content\SupportFiles", "$PredecessorPath\SupportFiles") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $predSupport) {
        $any = Get-ChildItem -LiteralPath $PredecessorPath -Directory -Recurse -Filter 'SupportFiles' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($any) { $predSupport = $any.FullName }
    }
    if (-not $predSupport) { return 0 }
    $asFiles = @(Get-ChildItem -LiteralPath $predSupport -File -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension -ieq '.ps1' -and $_.Name -match '(?i)ActiveSetup' })
    if (-not $asFiles.Count) { return 0 }
    if (-not (Test-Path $SupportDir)) { New-Item $SupportDir -ItemType Directory -Force | Out-Null }
    $n = 0
    foreach ($f in $asFiles) {
        # Swap the current version (pred -> new) in BOTH the filename and the content, matching the reused script's
        # reference. (Pred-of-pred bumping is left to the main script per the checkbox rule; an Active Setup stub almost
        # never carries a two-versions-back reference, so keeping it simple here avoids the checkbox coupling.)
        $newName = Invoke-VersionSwap -Text $f.Name -OldVersion $PredVersion -NewVersion $newVer
        $content = [IO.File]::ReadAllText($f.FullName)
        $content = Invoke-VersionSwap -Text $content -OldVersion $PredVersion -NewVersion $newVer
        [IO.File]::WriteAllText((Join-Path $SupportDir $newName), $content, (New-Object System.Text.UTF8Encoding $true))
        Write-Log "Active Setup carried from predecessor: $($f.Name) -> SupportFiles\$newName (version-swapped name + content)" Success
        $n++
    }
    return $n
}

# GPF request drops sometimes nest ANOTHER 'Files' folder inside Sources\Files, which the structure-preserving copy
# lands as Content\Files\Files\... - hoist the inner folder's CONTENTS up one level (never overwrite an existing
# name; the inner folder is removed only when fully emptied). Safe no-op when there is no nested Files folder.
function Invoke-NestedFilesHoist {
    param([Parameter(Mandatory)][string]$FilesDir)
    $nested = Join-Path $FilesDir 'Files'
    if (-not ((Test-Path -LiteralPath $nested) -and (Get-Item -LiteralPath $nested).PSIsContainer)) { return }
    $moved = 0; $left = 0
    foreach ($it in @(Get-ChildItem -LiteralPath $nested -Force -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $FilesDir $it.Name
        if (Test-Path -LiteralPath $dest) { $left++; continue }
        Move-Item -LiteralPath $it.FullName -Destination $dest -Force
        $moved++
    }
    if (-not (Get-ChildItem -LiteralPath $nested -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $nested -Force }
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        $clash = if ($left) { " ($left name-clash item(s) left in place - review)" } else { '' }
        Write-Log "Nested Files\Files detected in the payload - hoisted $moved item(s) up into Content\Files$clash."
    }
}

# v4 standard layout: SupportFiles is a SIBLING of Files (Content\SupportFiles), NEVER nested inside it. Some payloads
# (and predecessor carries) land a SupportFiles folder under Content\Files; hoist it OUT to Content\SupportFiles so the
# package follows the template ($adtSession.DirSupportFiles = Content\SupportFiles: ActiveSetup stubs, HTML prompts, and
# other config; Files holds only the installer payload). Merges into an existing Content\SupportFiles (name-clash left in place).
function Invoke-SupportFilesHoist {
    param([Parameter(Mandatory)][string]$FilesDir, [Parameter(Mandatory)][string]$SupportDir)
    $nested = Join-Path $FilesDir 'SupportFiles'
    if (-not ((Test-Path -LiteralPath $nested) -and (Get-Item -LiteralPath $nested).PSIsContainer)) { return }
    if (-not (Test-Path -LiteralPath $SupportDir)) { New-Item $SupportDir -ItemType Directory -Force | Out-Null }
    $moved = 0; $left = 0
    foreach ($it in @(Get-ChildItem -LiteralPath $nested -Force -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $SupportDir $it.Name
        if (Test-Path -LiteralPath $dest) { $left++; continue }
        Move-Item -LiteralPath $it.FullName -Destination $dest -Force
        $moved++
    }
    if (-not (Get-ChildItem -LiteralPath $nested -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $nested -Force }
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        $clash = if ($left) { " ($left name-clash item(s) left in place - review)" } else { '' }
        Write-Log "SupportFiles nested under Content\Files - hoisted $moved item(s) out to Content\SupportFiles (v4 layout)$clash."
    }
}

# MRF (ModulePack Request form) target name: "<original base minus any prior _[<brandprefix>_]<vendor>_... suffix>_<PackageFullName><ext>".
# The optional [A-Za-z0-9]{2,5}_ before the vendor lets the strip also remove a brand prefix (INA_/VWG_/G1V_) that a
# PRIOR rename appended - so a re-run with a PREFIXED FullName stays idempotent (no "..._INA_INA_ZSCALER..." doubling).
function Get-MrfTargetName {
    param([string]$FileBaseName, [string]$Vendor, [string]$FullName, [string]$Ext)
    $core = if ($Vendor) { [regex]::Replace($FileBaseName, '(?i)_(?:[A-Za-z0-9]{2,5}_)?' + [regex]::Escape($Vendor) + '_.*$', '') } else { $FileBaseName }
    return "${core}_${FullName}${Ext}"
}

# The package's Documents folder must hold ONLY the CURRENT request's documents, never a predecessor's. Any doc item
# sitting under (or being) a "Predecessor" folder is dropped. Matches both a folder item that IS the predecessor folder
# (path ends "...\Predecessor") and a file harvested from inside it ("...\Predecessor\install.pdf"), on \ or /.
function Remove-PredecessorDocItems {
    param([object[]]$DocItems)
    @(@($DocItems) | Where-Object { $_ -and ("$_" -notmatch '(?i)[\\/]predecessor([\\/]|$)') })
}

function New-Package {
    param(
        [Parameter(Mandatory)][hashtable]$NewPkg,        # identity + installer info (FullName, Vendor, AppName, Arch, MsiFileName...)
        [Parameter(Mandatory)][string]$ScriptText,       # final Invoke-AppDeployToolkit.ps1 content (Step 3)
        [hashtable]$Resolved,                            # Resolve-Source result
        [object[]]$ChosenInstallers = @(),
        [bool]$LooseFiles = $false,
        [string]$OutputBase,
        [string]$TemplateRoot,
        [bool]$RemoveShortcut = $false, [bool]$RemoveRun32 = $false, [bool]$RemoveRun64 = $false,
        [bool]$RemoveStartup = $false, [bool]$RemoveStray = $false,
        [bool]$CreateArp = $false, [object[]]$ShortcutTargets = @(),
        [hashtable]$MsiPropsMap = @{},          # MSI filename -> "KEY=VALUE; ..." extra properties
        [hashtable]$MsiFlagsMap = @{},          # MSI filename -> @{ Shortcut=<remove?>; Run=<remove?> } (per MSI)
        [object[]]$MstApplyExtras = @(),        # user-confirmed predecessor MST removals (single-MSI reuse)
        [string]$PredecessorPath = '',          # reuse: carry the predecessor's Active Setup .ps1 forward (version-swapped)
        [string]$PredVersion = '',              # reuse: the predecessor version, for the Active Setup name/content swap
        [bool]$GenerateMst = $true              # F27/F29: build an MST per MSI (transform+cleanup). $false -> reuse the source MST if present, else plain MSI.
    )
    # UNIVERSAL predecessor-doc guard: the package's Documents folder must hold ONLY the CURRENT request's documents,
    # never a predecessor's. Fetch-mode already filters, but a MANUAL installer pick (or any brand) can carry docs that
    # were harvested from a sibling/parent tree containing a "Predecessor" folder. Strip them here - the single build-time
    # choke point every copy path (direct copy below + Copy-ResolvedSource) flows through - so it holds for every mode.
    if ($Resolved -and $Resolved.DocItems) {
        $Resolved.DocItems = Remove-PredecessorDocItems -DocItems @($Resolved.DocItems)
    }
    if (-not $OutputBase) { $OutputBase = Get-Setting 'OutputBasePath' 'c:\temp' }
    $pkgName = "$($NewPkg.FullName)"
    if (-not $pkgName) { Write-Log "No package FullName - cannot create." Error; return $null }
    # GPF: the OUTPUT FOLDER carries the target-brand prefix (INA_/VWG_/G1V_) - the AppFullName inside the
    # script stays UNPREFIXED (their log names prove it). NewPkg.OutPrefix comes from the Step-4 prefix picker.
    if ("$($NewPkg.OutPrefix)".Trim()) { $pkgName = "$($NewPkg.OutPrefix.Trim())_$pkgName" }
    $pkgPath = Join-Path $OutputBase $pkgName
    # REBUILDS: a previous build may already sit at $pkgPath. Stale files (old version-named
    # MSI/EXE/zip and their MSTs) would survive the overlay copy and SHIP in the new content,
    # so clean first - but ONLY when the folder is clearly OUR previous output (it contains
    # Content\Invoke-AppDeployToolkit.ps1) or is empty. Anything else we refuse to touch.
    if (Test-Path $pkgPath) {
        $hasItems = [bool](Get-ChildItem -LiteralPath $pkgPath -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
        $isOurs   = Test-Path (Join-Path $pkgPath 'Content\Invoke-AppDeployToolkit.ps1')
        if ($hasItems -and -not $isOurs) {
            Write-Log "Output folder exists but is NOT a previous build: $pkgPath - refusing to overwrite. Move/rename it or change OutputBasePath." Error
            return $null
        }
        if ($hasItems) {
            Write-Log "Previous build found at $pkgPath - cleaning it so no stale installers/MSTs ship in the rebuild."
            Remove-Item -Path (Join-Path $pkgPath '*') -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Ensure-Dir $pkgPath
    Write-Log "Assembling package: $pkgPath"

    # 1. Lay down the blank template (Content/ + Documents/ + Icons/).
    $tpl = Get-TemplateRoot -Root $TemplateRoot
    if (-not $tpl.Path) { Write-Log "Blank template not found (PSADT_Template\ or .zip)." Error; return $null }
    try { Copy-Item -Path "$($tpl.Path)\*" -Destination $pkgPath -Recurse -Force }
    finally { if ($tpl.Temp -and (Test-Path $tpl.Temp)) { Remove-Item $tpl.Temp -Recurse -Force -ErrorAction SilentlyContinue } }

    $contentDir = Join-Path $pkgPath 'Content'
    $filesDir   = Join-Path $contentDir 'Files'
    # (Invoke-NestedFilesHoist below flattens a Files\Files payload after the source copy.)
    $supportDir = Join-Path $contentDir 'SupportFiles'
    $docsDir    = Join-Path $pkgPath 'Documents'
    $iconsDir   = Join-Path $pkgPath 'Icons'
    foreach ($d in @($filesDir, $supportDir, $docsDir, $iconsDir)) { Ensure-Dir $d }

    # 2. Write the Step-3 script (UTF-8 with BOM, CRLF - PSADT convention).
    $ps1 = Join-Path $contentDir 'Invoke-AppDeployToolkit.ps1'
    [IO.File]::WriteAllText($ps1, $ScriptText, (New-Object System.Text.UTF8Encoding $true))
    Write-Log "Wrote $ps1"

    # 2b. Per-user Active Setup: stage the plain-PowerShell stub into SupportFiles. The generated ps1 copies it to a
    #     persistent dir and registers Set-ADTActiveSetup; the stub is a ready-to-edit template (the packager fills in
    #     this app's HKCU settings). Name matches what Get-PerUserConfig wrote into the script.
    if ("$($NewPkg.PerUserMode)" -eq 'ActiveSetup' -and (Get-Command Get-ActiveSetupStub -EA SilentlyContinue)) {
        try {
            $stubName = Get-ActiveSetupStubName -AppName "$($NewPkg.AppName)" -Version "$($NewPkg.Version)"
            $stubText = Get-ActiveSetupStub     -AppName "$($NewPkg.AppName)" -Version "$($NewPkg.Version)" -Vendor "$($NewPkg.Vendor)" -HkcuItems @($NewPkg.Hkcu)
            [IO.File]::WriteAllText((Join-Path $supportDir $stubName), $stubText, (New-Object System.Text.UTF8Encoding $true))
            Write-Log "Active Setup stub -> SupportFiles\$stubName" Success
        } catch { Write-Log "Could not write Active Setup stub: $($_.Exception.Message)" Warning }
    }
    # 2b'. Predecessor reuse: carry forward the predecessor's Active Setup .ps1 (renamed + content version-swapped to
    #      the new version), so the reused script's Copy-ADTFile "...<newver>_ActiveSetup_Install.ps1" reference resolves.
    if ($PredecessorPath -and $PredVersion) {
        try { [void](Copy-PredecessorActiveSetup -PredecessorPath $PredecessorPath -SupportDir $supportDir -NewPkg $NewPkg -PredVersion $PredVersion) }
        catch { Write-Log "Active Setup carry-forward failed: $($_.Exception.Message)" Warning }
    }
    # 2c. Per-user FILES the snapshot detected -> stage into SupportFiles\UserProfile\<Scope>\... so the generated
    #     Get-ADTUserProfiles copy loop (Get-PerUserFileCopy) can fan them out to every profile at install.
    if (@($NewPkg.UserFiles).Count -and (Get-Command Get-PerUserFileCopy -EA SilentlyContinue)) {
        $n = 0
        foreach ($st in @((Get-PerUserFileCopy -Files @($NewPkg.UserFiles)).Staged)) {
            try {
                if (-not (Test-Path -LiteralPath $st.Source)) { continue }
                $dest = Join-Path $supportDir $st.Rel
                $dd = Split-Path $dest -Parent; if ($dd -and -not (Test-Path $dd)) { New-Item $dd -ItemType Directory -Force | Out-Null }
                Copy-Item -LiteralPath $st.Source -Destination $dest -Force
                $n++
            } catch { Write-Log "Could not stage per-user file $($st.Source): $($_.Exception.Message)" Warning }
        }
        if ($n) { if (Get-Command Unblock-PBPath -EA SilentlyContinue) { Unblock-PBPath -Path (Join-Path $supportDir 'UserProfile') }; Write-Log "Staged $n per-user file(s) -> SupportFiles\UserProfile" Success }
    }

    # 3. Source -> Files\  (zip for loose, otherwise installers + payload).
    if ("$($NewPkg.InstallerMode)" -eq 'ZipPayload' -and "$($Resolved.ZipPayload)".Trim() -and (Test-Path -LiteralPath "$($Resolved.ZipPayload)")) {
        # GPF ZIP PAYLOAD: copy the source .zip VERBATIM into Files\ under its own name (Files\Files.zip stays Files.zip) -
        # NO extraction, NO re-zip. The ps1 Expand-ZipFile's it to $envTemp\<App>_<Ver> at install and runs the selected
        # installer(s). Docs/icons still come across.
        $zpName = [IO.Path]::GetFileName("$($Resolved.ZipPayload)")
        Copy-Item -LiteralPath "$($Resolved.ZipPayload)" -Destination (Join-Path $filesDir $zpName) -Force
        Write-Log "ZIP payload -> Files\$zpName (kept verbatim, extracted at install)." Success
        if ($Resolved) {
            foreach ($item in @($Resolved.DocItems)) { if ($item -and (Test-Path $item)) { Copy-Item -LiteralPath $item -Destination $docsDir -Recurse -Force } }
            if ($Resolved.IconsPath -and (Test-Path $Resolved.IconsPath)) { Copy-Item -Path "$($Resolved.IconsPath)\*" -Destination $iconsDir -Recurse -Force }
        }
    }
    elseif ($LooseFiles) {
        $srcRoot = if ($Resolved -and $Resolved.PayloadRoot) { $Resolved.PayloadRoot } else { Get-CommonParent -Files $ChosenInstallers }
        if (-not $srcRoot -and $Resolved) { $srcRoot = $Resolved.RootPath }
        # F25/F34: preserve a zipped source's ORIGINAL name when set ($NewPkg.ZipName - GPF keeps the source's own name so
        # Files\ mirrors the incoming source), instead of renaming everything to <PackageName>.zip.
        $destZipName = if ("$($NewPkg.ZipName)".Trim()) { "$($NewPkg.ZipName)".Trim() } else { "$pkgName.zip" }
        if ($destZipName -notmatch '(?i)\.zip$') { $destZipName = "$destZipName.zip" }
        $zip = New-PayloadZip -PayloadFiles $ChosenInstallers -SrcRoot $srcRoot -DestZip (Join-Path $filesDir $destZipName)
        if ($zip) { Write-Log "Loose payload -> $zip" Success } else { Write-Log "Loose payload zip not created (no source root)." Warning }
        # docs + icons still come across for loose packages
        if ($Resolved) {
            foreach ($item in @($Resolved.DocItems)) { if ($item -and (Test-Path $item)) { Copy-Item -LiteralPath $item -Destination $docsDir -Recurse -Force } }
            if ($Resolved.IconsPath -and (Test-Path $Resolved.IconsPath)) { Copy-Item -Path "$($Resolved.IconsPath)\*" -Destination $iconsDir -Recurse -Force }
        }
    } else {
        Copy-ResolvedSource -Resolved $Resolved -ChosenInstallers $ChosenInstallers -InstallerDest $filesDir -DocDest $docsDir -IconDest $iconsDir
    }

    # 3a-fix (GPF request shape): some drops nest ANOTHER 'Files' folder inside Sources\Files - hoist it so the
    # payload sits directly in Content\Files (never Content\Files\Files).
    Invoke-NestedFilesHoist -FilesDir $filesDir
    # 3a-fix2 (v4 layout): a SupportFiles folder that landed under Content\Files is hoisted OUT to Content\SupportFiles
    # (the team's tests showed SupportFiles wrongly nested inside Files; v4 standard keeps them siblings).
    Invoke-SupportFilesHoist -FilesDir $filesDir -SupportDir $supportDir

    # 3a-fix3 (MRF name): the ModulePack Request form in Documents must carry the CURRENT package name
    # (finding: "MRF name should be updated with current package name") -> "<original base>_<PackageFullName>.xlsx".
    # Idempotent: an existing "_<vendor>_...<oldfullname>" suffix is stripped first, and an exact (case-sensitive)
    # match is left untouched; a case-only difference is corrected.
    # The MRF carries the FULL package name INCLUDING the brand prefix (the output folder is prefixed, e.g.
    # INA_ZSCALER_...), so the request form matches the package the team ships. No prefix (MTB) -> unprefixed as before.
    $mrfFull = "$(if("$($NewPkg.OutPrefix)".Trim()){"$($NewPkg.OutPrefix.Trim())_"})$($NewPkg.FullName)"; $mrfVendor = "$($NewPkg.Vendor)"
    if ($mrfFull -and $mrfVendor -and (Test-Path -LiteralPath $docsDir)) {
        foreach ($mrf in @(Get-ChildItem -LiteralPath $docsDir -File -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -match '(?i)^ModulePack Request' -and $_.Extension -match '(?i)^\.xlsx?$' })) {
            $base   = [IO.Path]::GetFileNameWithoutExtension($mrf.Name); $ext = $mrf.Extension
            $target = Get-MrfTargetName -FileBaseName $base -Vendor $mrfVendor -FullName $mrfFull -Ext $ext
            if ($mrf.Name -ceq $target) { continue }   # already exactly correct (case-sensitive)
            try {
                $tmp = Join-Path $docsDir ('~mrf_' + [guid]::NewGuid().ToString('N') + $ext)
                Rename-Item -LiteralPath $mrf.FullName -NewName (Split-Path $tmp -Leaf) -Force   # 2-step so a case-only rename works on Windows
                $dest = Join-Path $docsDir $target
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
                Rename-Item -LiteralPath $tmp -NewName $target -Force
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "MRF renamed -> $target (current package name)" Success }
            } catch { if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "MRF rename skipped: $($_.Exception.Message)" Warning } }
        }
    }

    # 3b. Icons: copy .ico/.png from the source Icons folder, generate .png from any lone .ico,
    #     and fall back to extracting from an EXE if still empty.
    Copy-PackageIcons -Resolved $Resolved -IconsDir $iconsDir -FilesDir $filesDir

    # 4. ARP icon -> SupportFiles\Icon.ico (icon priority resolved from Source.ps1).
    if ($CreateArp) {
        $targets = @($ShortcutTargets | Where-Object { $_ } | ForEach-Object { Join-Path $filesDir ("$_".TrimStart('\','/')) })
        $icon = Resolve-ArpIcon -Resolved $Resolved -TargetExes $targets -AppName "$($NewPkg.AppName)" -Vendor "$($NewPkg.Vendor)"
        if ($icon -and (Save-ArpIcon -IconSource $icon -SupportFilesDir $supportDir)) { Write-Log "ARP icon -> SupportFiles\Icon.ico (from $([IO.Path]::GetFileName($icon)))" Success }
        else { Write-Log "ARP icon not resolved - Set-MTBApplicationWizardEntry will have no icon." Warning }
    }

    # 5. MST for EVERY MSI in the package (each merges its own vendor MST + the Step-2 flags).
    # F27/F29: only when the packager kept "Generate MST" on. When off, any SOURCE mst was already copied flat into
    # Files\ (used as-is by the install command); if there was none, the MSI installs plain - either way we build NOTHING.
    if (-not $GenerateMst) {
        $srcMsts = @(Get-ChildItem -LiteralPath $filesDir -Filter *.mst -File -Recurse -ErrorAction SilentlyContinue)
        if ($srcMsts.Count) { Write-Log "MST generation OFF - reusing the source transform(s) as-is: $((@($srcMsts | ForEach-Object { $_.Name })) -join ', ')." }
        else { Write-Log "MST generation OFF and no source MST found - the MSI(s) install plain (no transform)." }
    }
    elseif (-not $LooseFiles -and (Get-Command Build-Mst -ErrorAction SilentlyContinue)) {
        $msis = @(Get-ChildItem -LiteralPath $filesDir -Filter *.msi -File -Recurse -ErrorAction SilentlyContinue)
        $runToPsadt = New-Object System.Collections.Generic.List[object]   # Run keys the MST kept (shared component) -> PSADT
        foreach ($msi in $msis) {
            # standard properties + this MSI's user-supplied extras
            $props = Get-StandardMstProperties
            if ($MsiPropsMap.ContainsKey($msi.Name)) {
                $extra = ConvertTo-MsiPropHashtable $MsiPropsMap[$msi.Name]
                foreach ($k in $extra.Keys) { $props[$k] = $extra[$k] }
            }
            # per-MSI cleanup flags (fall back to the package-level defaults when a specific flag isn't set for this MSI)
            $rmShort = $RemoveShortcut; $rmStartup = $RemoveStartup; $rmStray = $RemoveStray; $rmRun = $RemoveRun32
            if ($MsiFlagsMap.ContainsKey($msi.Name)) {
                $fl = $MsiFlagsMap[$msi.Name]
                if ($fl.ContainsKey('Shortcut')) { $rmShort   = [bool]$fl.Shortcut }
                if ($fl.ContainsKey('Startup'))  { $rmStartup = [bool]$fl.Startup }
                if ($fl.ContainsKey('Stray'))    { $rmStray   = [bool]$fl.Stray }
                if ($fl.ContainsKey('Run'))      { $rmRun     = [bool]$fl.Run }
            }
            New-PackageMst -MsiPath $msi.FullName -OutputDir (Split-Path $msi.FullName -Parent) -AppName "$($NewPkg.AppName)" `
                -ExistingMst (Find-VendorMst $msi.FullName) -Properties $props `
                -RemoveDesktopShortcut $rmShort -RemoveStartupShortcut $rmStartup -RemoveStrayShortcuts $rmStray `
                -RemoveRunKey32 $rmRun -RemoveRunKey64 $rmRun -ApplyExtras $MstApplyExtras -DeferredRunKeys $runToPsadt | Out-Null
        }
        if ($msis.Count -gt 0) { Write-Log "Built MST for $($msis.Count) MSI(s)." Success }
        # Run keys that shared an MSI component were KEPT in the MSI (deleting them would drop the component's other
        # resources) -> remove just the VALUE via PSADT post-install, written into the package's ps1.
        if ($runToPsadt.Count -and (Get-Command Add-PsadtRunKeyRemovals -ErrorAction SilentlyContinue)) {
            $n = Add-PsadtRunKeyRemovals -Ps1Path $ps1 -RunKeys $runToPsadt.ToArray()
            if ($n) { Write-Log "$n shared-component Run key(s) -> added Remove-ADTRegistryKey to POST-INSTALLATION (safer than deleting the component)." Success }
        }
    }

    # 6. Unblock everything we just wrote (strip Mark-of-the-Web / Zone.Identifier from network/SharePoint copies)
    #    via the shared helper, so the packaged installers run without a SmartScreen / security-warning prompt.
    if (Get-Command Unblock-PBPath -EA SilentlyContinue) { Unblock-PBPath -Path $pkgPath }
    else { try { Get-ChildItem -Path $pkgPath -Recurse -File -Force -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue } catch {} }

    Write-Log "Package ready: $pkgPath" Success
    return $pkgPath
}
