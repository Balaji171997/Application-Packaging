##############################################################
# BrandGpf.ps1 - GPF GroupWrapper brand: Incoming request-folder
# resolution. Their Incoming = one folder per ticket
#   "AES-1-0XXXXX-A <identity>"   (identity = Vendor_App_Arch_Ver-Rev_Lang OR free text)
# with VARIABLE subfolders (take max available info):
#   Sources\Files [+SupportFiles|'Support Files']  or one raw payload folder
#   Predecessor\<package>   (authoritative - they have NO live share access)
#   Icons\ (or a root icon.png) ; Docs_EQS\ / Documents\ ; Mails\ ; Shortcut Behavior\ ;
#   root *.xlsx forms (ModulePack Request / Complexity_Matrix) ; Vendor_Sources\ (reference only)
##############################################################

# Normalise a name for matching: lowercase, only letters+digits (kills _ - . and spaces).
function Get-GpfNameKey { param([string]$Name) return ("$Name".ToLower() -replace '[^a-z0-9]', '') }

# Strip the ticket prefix "AES-1-020436-A " from a request folder name -> the identity text.
function Split-GpfRequestName {
    param([string]$FolderName)
    $m = [regex]::Match("$FolderName", '^(?<aes>AES-\d+-\d+(?:-[A-Za-z0-9]+)?)\s+(?<id>.+)$')
    if ($m.Success) { return @{ Aes = $m.Groups['aes'].Value; Identity = $m.Groups['id'].Value.Trim() } }
    return @{ Aes = ''; Identity = "$FolderName".Trim() }
}

# Find the request folder for a package: match with OR without the AES prefix, tolerant of separators.
# $PackageName may be the full name (Vendor_App_Arch_Ver-Rev_Lang), a prefixed one, or free text.
function Find-GpfRequestFolder {
    param([string]$IncomingRoot, [string]$PackageName, [string]$Vendor = '', [string]$AppName = '')
    if (-not $IncomingRoot -or -not (Test-Path -LiteralPath $IncomingRoot)) { return $null }
    $wantKey = Get-GpfNameKey $PackageName
    $vaKey   = Get-GpfNameKey ("$Vendor$AppName")     # fallback: a typed STRUCTURED name vs a FREE-TEXT folder often only shares Vendor+App
    $best = $null; $bestScore = 0
    foreach ($d in (Get-ChildItem -LiteralPath $IncomingRoot -Directory -ErrorAction SilentlyContinue)) {
        $id = (Split-GpfRequestName $d.Name).Identity
        $idKey = Get-GpfNameKey $id
        if (-not $idKey) { continue }
        $score = 0
        if ($idKey -eq $wantKey) { $score = 100 }
        elseif ($wantKey -and ($wantKey.Contains($idKey) -or $idKey.Contains($wantKey))) { $score = 60 + [Math]::Min(30, $idKey.Length) }
        elseif ($vaKey -and $idKey.Contains($vaKey)) { $score = 50 }   # vendor+app hit ("Microsoft MECM Console 5.2509" vs Microsoft_MECMConsole_...)
        if ($score -gt $bestScore) { $bestScore = $score; $best = $d }
    }
    if ($bestScore -ge 50) { return $best.FullName }
    return $null
}

# Normalise a GPF predecessor FOLDER NAME to a parseable package identity:
#  - strip the target-brand prefix (INA_/VWG_/G1V_)
#  - fix the mangled revision separator some folders carry ("..._2503_0002_MUL" -> "..._2503-0002_MUL")
function Get-GpfPredecessorPackageName {
    param([string]$FolderName)
    $n = "$FolderName" -replace '^(G1V|INA|VWG)_', ''
    $n = [regex]::Replace($n, '_(\d+(?:\.\d+)*)_(\d{3,4})_([A-Za-z][A-Za-z-]*)$', '_$1-$2_$3')
    return $n
}

# Extract a ZIPPED predecessor package to the local work cache (cached - re-extract skipped) and return the INNER
# package root: the folder holding Content\Invoke-AppDeployToolkit.ps1 / Content\Deploy-Application.ps1 (or a top-level
# deployment script), else the extraction root. Returns '' when nothing usable is inside.
function Expand-GpfPredecessorZip {
    param([string]$ZipPath)
    if (-not $ZipPath -or -not (Test-Path -LiteralPath $ZipPath)) { return '' }
    try {
        # SHORT cache path (8-char hash, not the 40+ char package name) + MAX_PATH-safe extractor + re-extract when a prior
        # run left the cache empty/incomplete. See Get-PredZipCache / Expand-PBArchive (Core.ps1). Deeply-nested PSADT
        # packages zipped WITH a top folder named after themselves otherwise blow past 260 chars -> empty cache -> "Content
        # not found" on the reused stale folder.
        $cache = Get-PredZipCache -ZipPath $ZipPath
        if (-not (Test-Path -LiteralPath $cache) -or -not (Test-PredZipComplete -CacheDir $cache)) {
            if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue }
            [void](Expand-PBArchive -ZipPath $ZipPath -Destination $cache)
        }
        # Package ROOT = a folder holding Content\<script> (preferred) or a bare <script>. A folder named 'Content' is
        # NEVER the root (its PARENT is - a zip of a package folder's CONTENTS puts Content\ at the cache root). Check the
        # cache root FIRST, then recurse, excluding 'Content'-named folders from the bare-script match.
        $isRoot = {
            param($d)
            (Test-Path (Join-Path $d 'Content\Invoke-AppDeployToolkit.ps1')) -or
            (Test-Path (Join-Path $d 'Content\Deploy-Application.ps1')) -or
            (Test-Path (Join-Path $d 'Invoke-AppDeployToolkit.ps1')) -or
            (Test-Path (Join-Path $d 'Deploy-Application.ps1'))
        }
        $inner = $null
        if (& $isRoot $cache) { $inner = Get-Item -LiteralPath $cache }
        if (-not $inner) {
            $inner = Get-ChildItem -LiteralPath $cache -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
                        (Test-Path (Join-Path $_.FullName 'Content\Invoke-AppDeployToolkit.ps1')) -or
                        (Test-Path (Join-Path $_.FullName 'Content\Deploy-Application.ps1')) -or
                        ($_.Name -ne 'Content' -and ((Test-Path (Join-Path $_.FullName 'Invoke-AppDeployToolkit.ps1')) -or
                                                     (Test-Path (Join-Path $_.FullName 'Deploy-Application.ps1')))) } | Select-Object -First 1
        }
        if ($inner) { return $inner.FullName }
    } catch {}
    return ''
}

# The request's Predecessor CONTAINER - the folder that holds the predecessor package(s). Handles BOTH forms of the
# predecessor folder: a NORMAL "<Request>\Predecessor\" folder, OR a ZIPPED whole folder "<Request>\Predecessor*.zip"
# (extracted to the work cache; if the zip itself wraps a "Predecessor" folder, that inner folder is returned). The
# package(s) inside can then be normal subfolders OR zips - enumerated by the callers. Returns '' when none.
function Get-GpfPredecessorContainer {
    param([string]$RequestPath)
    if (-not $RequestPath) { return '' }
    foreach ($pn in 'Predecessor','predecessor') {
        $pp = Join-Path $RequestPath $pn
        if (Test-Path -LiteralPath $pp -PathType Container) { return $pp }
    }
    $z = @(Get-ChildItem -LiteralPath $RequestPath -Filter '*.zip' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.BaseName -match '(?i)^predecessor' } | Sort-Object Name -Descending)
    if ($z.Count) {
        try {
            # SHORT cache + MAX_PATH-safe extract (see Core.ps1). A whole "Predecessor.zip" wraps deeply-nested packages;
            # extracting under the long zip name blows past 260 chars and leaves an empty cache.
            $cache = Get-PredZipCache -ZipPath $z[0].FullName
            if (-not (Test-Path -LiteralPath $cache) -or -not (@(Get-ChildItem -LiteralPath $cache -Force -ErrorAction SilentlyContinue).Count)) {
                if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue }
                [void](Expand-PBArchive -ZipPath $z[0].FullName -Destination $cache)
            }
            $inPred = Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^predecessor$' } | Select-Object -First 1
            if ($inPred) { return $inPred.FullName }
            return $cache
        } catch { return '' }
    }
    return ''
}

# FUZZY name matching for predecessor detection. The GPF request's Predecessor\ folder is CURATED by the team, but the
# predecessor's Vendor_AppName often differs slightly from the NEW package's (spelling, spacing, casing, a trailing token,
# a renamed vendor) - an EXACT compare then wrongly rejects a valid, hand-placed predecessor and the user sees "no
# predecessor". Normalise to lowercase alphanumerics and accept an exact key, a substring either way, or a high
# Levenshtein similarity (default 0.82).
function Get-GpfNameKey {
    param([string]$Vendor, [string]$AppName)
    return (("$Vendor" + "$AppName") -replace '[^A-Za-z0-9]', '').ToLower()
}
function Get-GpfLevenshtein {
    param([string]$A, [string]$B)
    $n = "$A".Length; $m = "$B".Length
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }
    $prev = New-Object 'int[]' ($m + 1)
    $cur  = New-Object 'int[]' ($m + 1)
    for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $cur[0] = $i
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $cur[$j] = [Math]::Min([Math]::Min($cur[$j - 1] + 1, $prev[$j] + 1), $prev[$j - 1] + $cost)
        }
        $tmp = $prev; $prev = $cur; $cur = $tmp
    }
    return $prev[$m]
}
function Test-GpfNameFuzzyMatch {
    param([string]$NewVendor, [string]$NewApp, [string]$PredVendor, [string]$PredApp, [double]$Threshold = 0.82)
    $a = Get-GpfNameKey -Vendor $NewVendor -AppName $NewApp
    $b = Get-GpfNameKey -Vendor $PredVendor -AppName $PredApp
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    if ($a.Contains($b) -or $b.Contains($a)) { return $true }        # one name is a prefix/substring of the other
    $max = [Math]::Max($a.Length, $b.Length)
    if ($max -le 0) { return $false }
    $sim = 1.0 - ([double](Get-GpfLevenshtein -A $a -B $b) / $max)
    return ($sim -ge $Threshold)
}

# TARGET BRAND for a GPF build - one of 'INA' (Audi), 'VWG' (Group), 'G1V' (VW). The Step-1 dropdown stores the choice in
# $NewPkg.TargetBrand; if absent we auto-detect from a leading "<PREFIX>_" on the package name, else default to 'VWG'.
function Get-GpfTargetBrand {
    param($NewPkg)
    $b = "$($NewPkg.TargetBrand)".Trim().ToUpper()
    if ($b -in 'INA','VWG','G1V') { return $b }
    $nm = "$($NewPkg.FullName)"; if (-not $nm) { $nm = "$($NewPkg.AppName)" }
    $mm = [regex]::Match("$nm", '^(INA|VWG|G1V)_')
    if ($mm.Success) { return $mm.Groups[1].Value.ToUpper() }
    return 'VWG'
}

# InstallTitle for a FRESH GPF package (finding #13). Rules:
#  - VW (G1V) only: the vendor shown in the title is "Volkswagen", not the real manufacturer (title ONLY - every other
#    field keeps the real vendor).
#  - ALL brands: when the real Vendor and AppName are identical, don't repeat it - keep a single name token.
# Predecessor reuse does NOT use this (it carries the predecessor's own title + arch-suffix style).
function Get-GpfInstallTitle {
    param($NewPkg, [string]$Brand)
    $vendor = "$($NewPkg.Vendor)".Trim(); $app = "$($NewPkg.AppName)".Trim(); $ver = "$($NewPkg.Version)".Trim()
    $titleVendor = if ($Brand -eq 'G1V') { 'Volkswagen' } else { $vendor }
    if ($vendor -and ($vendor -ieq $app)) { return ("$titleVendor $ver").Trim() }   # don't repeat identical vendor/app
    return ("$titleVendor $app $ver").Trim()
}

# Audi (INA) only (finding #16): the processes the packager would close interactively must instead be closed SILENTLY -
# move the wrapper's VWG_ProcToClose value into VWG_ProcToCloseNonUI and blank VWG_ProcToClose. No-op for other brands or
# when ProcToClose is already empty. Idempotent.
function Set-GpfProcToCloseNonUI {
    param([string]$Text, [string]$Brand)
    if ($Brand -ne 'INA' -or -not $Text) { return $Text }
    $mC = [regex]::Match($Text, '(?im)^([ \t]*\[string\[\]\][ \t]*\$Global:VWG_ProcToClose\b[ \t]*=[ \t]*)(@\([^\r\n]*\)|''[^''\r\n]*''|"[^"\r\n]*")')
    if (-not $mC.Success) { return $Text }
    $val = $mC.Groups[2].Value
    if ($val -match '^\s*@\(\s*\)\s*$' -or $val -match "^\s*(''|`"`")\s*$") { return $Text }   # nothing to move
    # put the value into ProcToCloseNonUI (only if that line is currently empty), then blank ProcToClose
    $Text = [regex]::Replace($Text, '(?im)^([ \t]*\[string\[\]\][ \t]*\$Global:VWG_ProcToCloseNonUI\b[ \t]*=[ \t]*)(@\(\s*\)|''\s*''|"\s*")',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + $val })
    $Text = $Text.Remove($mC.Groups[2].Index, $mC.Groups[2].Length).Insert($mC.Groups[2].Index, '@()')
    return $Text
}

# Group (VWG) only (finding #14): Manufacturer + Product + Version + Language code must not exceed 34 characters (MECM
# name-length limit for the Group brand). Returns the total length; the caller warns when it exceeds 34.
function Get-GpfVwgNameLength {
    param($NewPkg)
    return (("$($NewPkg.Vendor)" + "$($NewPkg.AppName)" + "$($NewPkg.Version)" + "$($NewPkg.Lang)").Length)
}

# Predecessor candidates for a GPF build - same object shape as Get-PredecessorCandidates, but:
#  1. the request's OWN Predecessor\ folder comes FIRST (authoritative - the team has NO live share access);
#  2. the Outgoing scan tolerates the brand prefix + mangled revision in folder names;
#  3. Vendor_AppName is matched FUZZILY (curated folder + slight naming differences must still match).
# Name = the NORMALISED (parseable) identity; FullName = the real path (Read-PredecessorModel gets both).
function Get-GpfPredecessorCandidates {
    param($Parsed, $Request)
    $newFull = "$($Parsed.FullName)"
    $seen = @{}
    $addCand = {
        param($Dir, $Target)
        $norm = Get-GpfPredecessorPackageName $Dir.Name
        if ($norm -ieq $newFull) { return }                    # never offer the package as its OWN predecessor
        # dedupe by NORMALISED PACKAGE NAME (not path): the request's Predecessor\ copy and the Outgoing copy are the
        # SAME package in two places - offer it ONCE (the request entry is added first, so it wins).
        if ($seen.ContainsKey($norm.ToLower())) { return }
        $p = Parse-PackageName $norm
        if (-not $p.IsValid) { return }
        # FUZZY Vendor_AppName match (was an exact -ine compare that rejected hand-placed predecessors on any tiny naming
        # difference). The Predecessor\ folder is curated, so a close match is what the team intends to reuse.
        if (-not (Test-GpfNameFuzzyMatch -NewVendor $Parsed.Vendor -NewApp $Parsed.AppName -PredVendor $p.Vendor -PredApp $p.AppName)) { return }
        $seen[$norm.ToLower()] = $true
        try { $v = [version]($p.Version -replace '[^0-9.]','') } catch { $v = $null }
        [void]$Target.Add([pscustomobject]@{
            Name=$norm; FullName=$Dir.FullName; Version=$p.Version; Ver=$v
            Revision=$p.Release; SameVersion=($p.Version -eq $Parsed.Version)
        })
    }
    # The request's Predecessor\ folder ONLY (user rule): the GPF team has no live access and shares must never be
    # scanned automatically. Offer EVERY predecessor package in that folder (e.g. GlobalProtect ships 6.2.4 / 6.2.5 /
    # 6.2.8-0001 / 6.2.8-0002 - the packager picks which one to reuse), newest first. When the request offers nothing,
    # the BtnPred manual-browse popup is the fallback.
    $fromRequest = New-Object System.Collections.Generic.List[object]
    if ($Request -and "$($Request.PredecessorRoot)" -and (Test-Path -LiteralPath "$($Request.PredecessorRoot)")) {
        $root = "$($Request.PredecessorRoot)"
        # (a) NORMAL package subfolders
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) { & $addCand $dir $fromRequest }
        # (b) ZIPPED packages inside the Predecessor folder - extract each (cached) and offer the inner package
        foreach ($zip in @(Get-ChildItem -LiteralPath $root -Filter '*.zip' -File -ErrorAction SilentlyContinue)) {
            $inner = Expand-GpfPredecessorZip -ZipPath $zip.FullName
            if ($inner -and (Test-Path -LiteralPath $inner)) { & $addCand (Get-Item -LiteralPath $inner) $fromRequest }
        }
        # (c) the container IS itself a single package (Content\ at its root, no sub-packages)
        if (-not $fromRequest.Count -and ((Test-Path (Join-Path $root 'Content')) -or (Test-Path (Join-Path $root 'Deploy-Application.ps1')) -or (Test-Path (Join-Path $root 'Invoke-AppDeployToolkit.ps1')))) {
            & $addCand (Get-Item -LiteralPath $root) $fromRequest
        }
    }
    # The single resolved PredecessorPath (a normal folder or an already-extracted zip) - add it too (dedup by name).
    if ($Request -and "$($Request.PredecessorPath)" -and (Test-Path -LiteralPath "$($Request.PredecessorPath)")) {
        & $addCand (Get-Item -LiteralPath "$($Request.PredecessorPath)") $fromRequest
    }
    # Newest first (the default selection logic then picks the newest strictly-older-than-new). Piping the List through
    # Sort-Object enumerates it safely (a bare @($list) on a List[object] of PSObjects throws in PS 5.1).
    return @($fromRequest | Sort-Object { $_.Ver } -Descending)
}

# Harvest EVERYTHING usable from a request folder. Missing pieces stay empty - degrade gracefully.
# A GPF request folder looks like "<AES-id> <Vendor>_<App>_..._<lang>" and holds request markers (Sources\,
# Vendor_Sources\, Predecessor\, or a "ModulePack Request*.xlsx" form). When the user picks an installer BY HAND from
# inside such a tree (e.g. <Request>\Sources\Files\setup.msi), climb the ancestry to find that request root so the
# curated request documents (module request, install instructions, mails, Docs_EQS) are shipped exactly like the fetch
# flow - instead of an empty Documents folder. Returns the nearest qualifying ancestor, or '' if none within reach.
function Find-GpfRequestRoot {
    param([Parameter(Mandatory)][string]$StartPath, [int]$MaxHops = 6)
    $cur = $StartPath
    for ($i = 0; $i -lt $MaxHops -and $cur; $i++) {
        if (Test-Path -LiteralPath $cur) {
            $hasMarkerFolder = $false
            foreach ($mk in 'Sources','Vendor_Sources','Predecessor','predecessor') {
                if (Test-Path -LiteralPath (Join-Path $cur $mk)) { $hasMarkerFolder = $true; break }
            }
            $hasMrf = [bool](Get-ChildItem -LiteralPath $cur -File -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -match '(?i)^ModulePack Request' -and $_.Name -notmatch '^~\$' } | Select-Object -First 1)
            # Qualify only when the folder ALSO parses as a GPF request name (AES id + Vendor_App...), so a bare
            # "Sources" or a generic parent is never mistaken for the request root.
            $looksNamed = $false
            try { $p = Split-GpfRequestName (Split-Path $cur -Leaf); $looksNamed = [bool]($p -and $p.Identity) } catch {}
            if (($hasMarkerFolder -or $hasMrf) -and $looksNamed) { return $cur }
        }
        $up = Split-Path -Parent $cur
        if (-not $up -or $up -eq $cur) { break }
        $cur = $up
    }
    return ''
}

function Resolve-GpfRequest {
    param([Parameter(Mandatory)][string]$RequestPath)
    $name = Split-Path $RequestPath -Leaf
    $parts = Split-GpfRequestName $name
    $r = @{ RequestPath=$RequestPath; OrderNumber=$parts.Aes; IdentityText=$parts.Identity
            FilesDir=''; SupportDir=''; PayloadRoot=''; VendorSourcesDir=''; IconFiles=@(); DocItems=@(); PredecessorPath=''; PredecessorRoot=''
            Notes=(New-Object System.Collections.Generic.List[string]) }

    # --- Sources: Files/SupportFiles (pre-shaped), 'Support Files' variant, or ONE raw payload folder ---
    $src = Join-Path $RequestPath 'Sources'
    if (Test-Path -LiteralPath $src) {
        $f = Join-Path $src 'Files';        if (Test-Path -LiteralPath $f) { $r.FilesDir = $f }
        $s = Join-Path $src 'SupportFiles'; if (Test-Path -LiteralPath $s) { $r.SupportDir = $s }
        if (-not $r.SupportDir) { $s2 = Join-Path $src 'Support Files'; if (Test-Path -LiteralPath $s2) { $r.SupportDir = $s2 } }
        # NESTED Files\Files: when the Files folder has NO installers at its top but holds another 'Files' folder,
        # descend so the package gets the CONTENTS (never Content\Files\Files). Unreliable/deeper layouts stay as-is.
        $hops = 0
        while ($r.FilesDir -and $hops -lt 2) {
            $topInst = @(Get-ChildItem -LiteralPath $r.FilesDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '(?i)^\.(msi|exe|msp)$' })
            $innerF  = Join-Path $r.FilesDir 'Files'
            if (-not $topInst.Count -and (Test-Path -LiteralPath $innerF)) {
                $r.FilesDir = $innerF; $hops++
                [void]$r.Notes.Add("Files contained another Files folder - using the INNER one so contents land directly in Content\Files")
            } else { break }
        }
        if (-not $r.FilesDir) {
            # raw shape: a single payload folder (e.g. MECM_Console_2509_OFF) or loose files directly in Sources
            $subs = @(Get-ChildItem -LiteralPath $src -Directory -ErrorAction SilentlyContinue)
            $loose = @(Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue)
            if ($subs.Count -eq 1 -and -not $loose.Count) { $r.PayloadRoot = $subs[0].FullName; [void]$r.Notes.Add("Sources is a raw folder '$($subs[0].Name)' - used as the payload root") }
            elseif ($loose.Count) { $r.PayloadRoot = $src; [void]$r.Notes.Add('Sources holds loose files - used as the payload root') }
            elseif ($subs.Count -gt 1) { $r.PayloadRoot = $src; [void]$r.Notes.Add("Sources has $($subs.Count) folders and no Files\ - review which is the payload") }
        }
    } else { [void]$r.Notes.Add('No Sources folder in the request - choose the source manually') }
    # VENDOR_SOURCES: the raw vendor drop. Files/SupportFiles come FIRST; Vendor_Sources is the fallback payload
    # when the request has neither - and it is ALWAYS searched for install-instruction documents (below).
    $vend = Join-Path $RequestPath 'Vendor_Sources'
    if (Test-Path -LiteralPath $vend) {
        $r.VendorSourcesDir = $vend
        if (-not $r.FilesDir -and -not $r.PayloadRoot) {
            $vsubs = @(Get-ChildItem -LiteralPath $vend -Directory -ErrorAction SilentlyContinue)
            if ($vsubs.Count -eq 1) { $r.PayloadRoot = $vsubs[0].FullName; [void]$r.Notes.Add("No Sources payload - falling back to Vendor_Sources\$($vsubs[0].Name)") }
            elseif ($vsubs.Count -gt 1 -or (Get-ChildItem -LiteralPath $vend -File -EA SilentlyContinue)) { $r.PayloadRoot = $vend; [void]$r.Notes.Add('No Sources payload - falling back to Vendor_Sources (review the payload)') }
        }
    }

    # --- Icons: Icons\ folder, else any icon/ico/png at the request root ---
    $ic = Join-Path $RequestPath 'Icons'
    if (Test-Path -LiteralPath $ic) {
        $r.IconFiles = @(Get-ChildItem -LiteralPath $ic -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Extension -match '^\.(ico|png)$' -and $_.Name -ne 'Thumbs.db' } | ForEach-Object { $_.FullName })
    }
    if (-not $r.IconFiles.Count) {
        $r.IconFiles = @(Get-ChildItem -LiteralPath $RequestPath -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '(?i)^icon.*\.(ico|png)$' } | ForEach-Object { $_.FullName })
    }

    # --- Documents: the CURATED set the team wants shipped = Docs_EQS + Mails folders, the ModulePack Request form (root
    # xlsx/docx/msg), and install instructions (below). NOT wanted: Complexity Matrix, 'Shortcut Behavior', Icons, Sources,
    # Vendor_Sources, Thumbs.db, Office ~$ lock files, or anything under Predecessor. ('Documents' kept for requests that
    # use that folder name.) ---
    $docs = New-Object System.Collections.Generic.List[string]
    foreach ($dn in 'Docs_EQS','Documents','Mails') {
        $p = Join-Path $RequestPath $dn
        if (Test-Path -LiteralPath $p) { [void]$docs.Add($p) }
    }
    foreach ($f in (Get-ChildItem -LiteralPath $RequestPath -File -ErrorAction SilentlyContinue)) {
        # The Complexity Matrix is an internal effort-estimation sheet - the team does NOT want it shipped inside the
        # package's Documents folder (finding: "Complexity matrix can be ignored from incoming location to document
        # folder of package"). Everything else (ModulePack Request form, mails, instructions) is still collected.
        if ($f.Name -match '(?i)complexity') { continue }
        if ($f.Name -match '^~\$') { continue }   # Office lock file (e.g. ~$ModulePack Request.xlsx) - never a real doc
        if ($f.Extension -match '(?i)^\.(xlsx|docx|pdf|msg|txt)$') { [void]$docs.Add($f.FullName) }
    }
    # INSTALL INSTRUCTIONS: usually shipped inside the application folders - mostly Vendor_Sources - as a document.
    # Search the payload trees for instruction-named docs and bring the FILES into Documents. CURRENT request only
    # (predecessor documents are never fetched).
    # Paths to EXCLUDE from document harvesting: a "Predecessor" folder (only the CURRENT request's docs belong in the
    # package) AND any folder whose name contains "dependency"/"dependencies" (team rule: never copy documents/files out of
    # a dependency folder - they belong to a bundled dependency app, not this package). Matches the word anywhere in a
    # path SEGMENT ('App_Dependencies', '3rd Party Dependency', ...); the 'c' in "dependenc" avoids matching "independent".
    $excludeDoc = '(?i)([\\/]predecessor[\\/]|[\\/][^\\/]*dependenc)'
    foreach ($root in @($r.VendorSourcesDir, $src, $r.PayloadRoot) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique) {
        foreach ($d in (Get-ChildItem -LiteralPath $root -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -match '(?i)^\.(docx|doc|pdf|txt)$' -and
                                       $_.FullName -notmatch $excludeDoc -and   # CURRENT request only - never a predecessor's / dependency's doc
                                       # Install-instruction doc names. The team may also NAME the instructions document
                                       # "Software Package Request Form" (alternative), so it counts as install instructions too.
                                       $_.BaseName -match '(?i)install.*instru|instru.*install|installation.*guide|install.?instructions|how.?to.?install|software.?package.?request' })) {
            if (-not ($docs -contains $d.FullName)) { [void]$docs.Add($d.FullName); [void]$r.Notes.Add("Install instructions found: $($d.Name) (from $((Split-Path $root -Leaf)))") }
        }
    }
    # Final guard: NEVER ship a predecessor's OR a dependency folder's document. Drop any collected item under such a folder
    # (team finding: only the CURRENT request's own documents belong in the package's Documents folder).
    $r.DocItems = @($docs | Where-Object { "$_" -notmatch $excludeDoc })

    # --- Predecessor (source-location PRIORITY): the request's own Predecessor container - a normal "Predecessor\" folder
    # OR a zipped "Predecessor*.zip" whole folder. The package(s) inside may themselves be normal subfolders or zips.
    # PredecessorRoot = the container (candidate list enumerates ALL packages in it); PredecessorPath = the newest one. ---
    $pp = Get-GpfPredecessorContainer -RequestPath $RequestPath
    if ($pp) {
        $r.PredecessorRoot = $pp
        $subs = @(Get-ChildItem -LiteralPath $pp -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if ($subs.Count -ge 1) {
            $r.PredecessorPath = $subs[0].FullName
        } else {
            # no normal package subfolder - the package inside is ZIPPED (extract the newest), else the container itself is the package
            $zips = @(Get-ChildItem -LiteralPath $pp -Filter '*.zip' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
            if ($zips.Count -ge 1) {
                $inner = Expand-GpfPredecessorZip -ZipPath $zips[0].FullName
                if ($inner) { $r.PredecessorPath = $inner; [void]$r.Notes.Add("Predecessor package was ZIPPED ($($zips[0].Name)) - extracted to the local work cache") }
                else { [void]$r.Notes.Add("Predecessor zip '$($zips[0].Name)' extracted but no deployment script found inside - pick the predecessor manually") }
            } elseif ((Test-Path (Join-Path $pp 'Content')) -or (Test-Path (Join-Path $pp 'Deploy-Application.ps1')) -or (Test-Path (Join-Path $pp 'Invoke-AppDeployToolkit.ps1'))) {
                $r.PredecessorPath = $pp
            }
        }
    }
    $r.Notes = $r.Notes.ToArray()   # plain array out (no live List in the contract)
    return $r
}

# Predecessor for an app: request folder FIRST (authoritative), else the newest match in Outgoing.
# Outgoing names carry a brand prefix (INA_/VWG_/G1V_) and revisions are sometimes mangled (2503_0002 vs 2503-0002)
# -> match on the normalised Vendor+App key and ignore prefix/version separators.
function Find-GpfPredecessor {
    param([string]$RequestPath, [string]$OutgoingRoot, [string]$Vendor, [string]$AppName)
    if ($RequestPath) {
        $req = Resolve-GpfRequest -RequestPath $RequestPath
        if ($req.PredecessorPath) { return @{ Path=$req.PredecessorPath; From='request' } }
    }
    if (-not $OutgoingRoot -or -not (Test-Path -LiteralPath $OutgoingRoot)) { return $null }
    $wantKey = Get-GpfNameKey ("$Vendor$AppName")
    if (-not $wantKey) { return $null }
    $hits = @()
    foreach ($d in (Get-ChildItem -LiteralPath $OutgoingRoot -Directory -ErrorAction SilentlyContinue)) {
        $nm = $d.Name -replace '^(G1V|INA|VWG)_',''    # drop the brand prefix for matching
        $core = ($nm -split '_')                       # Vendor_App_Arch_Version-Rev_Lang
        if ($core.Count -ge 2) {
            $k = Get-GpfNameKey ($core[0] + $core[1])
            if ($k -eq $wantKey -or $k.Contains($wantKey) -or $wantKey.Contains($k)) { $hits += $d }
        }
    }
    if ($hits.Count) { return @{ Path=($hits | Sort-Object Name -Descending | Select-Object -First 1).FullName; From='outgoing' } }
    return $null
}

# Outgoing prefix for this brand from settings (INA=Gpf, VWG=Group package, G1V=VW). Returns ordered pairs.
function Get-GpfPrefixChoices {
    $p = Get-PBBrand -Path 'OutgoingPrefix' -Default $null
    $out = New-Object System.Collections.Generic.List[object]
    if ($p) {
        if ($p -is [hashtable] -or $p -is [System.Collections.Specialized.OrderedDictionary]) {
            foreach ($k in $p.Keys) { [void]$out.Add([pscustomobject]@{ Prefix="$k"; Label="$($p[$k])" }) }
        } else {
            foreach ($prop in $p.PSObject.Properties) { [void]$out.Add([pscustomobject]@{ Prefix="$($prop.Name)"; Label="$($prop.Value)" }) }
        }
    }
    return $out.ToArray()
}