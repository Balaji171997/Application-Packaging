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
        $cache = Join-Path (Get-WorkPath 'PredCache') ([IO.Path]::GetFileNameWithoutExtension($ZipPath))
        if (-not (Test-Path -LiteralPath $cache)) { Expand-Archive -LiteralPath $ZipPath -DestinationPath $cache -Force }
        $inner = Get-ChildItem -LiteralPath $cache -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
                    (Test-Path (Join-Path $_.FullName 'Content\Invoke-AppDeployToolkit.ps1')) -or
                    (Test-Path (Join-Path $_.FullName 'Content\Deploy-Application.ps1')) -or
                    (Test-Path (Join-Path $_.FullName 'Invoke-AppDeployToolkit.ps1')) -or
                    (Test-Path (Join-Path $_.FullName 'Deploy-Application.ps1')) } | Select-Object -First 1
        if (-not $inner -and ((Test-Path (Join-Path $cache 'Content')) -or (Test-Path (Join-Path $cache 'Deploy-Application.ps1')) -or (Test-Path (Join-Path $cache 'Invoke-AppDeployToolkit.ps1')))) { $inner = Get-Item -LiteralPath $cache }
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
            $cache = Join-Path (Get-WorkPath 'PredCache') ([IO.Path]::GetFileNameWithoutExtension($z[0].Name))
            if (-not (Test-Path -LiteralPath $cache)) { Expand-Archive -LiteralPath $z[0].FullName -DestinationPath $cache -Force }
            $inPred = Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^predecessor$' } | Select-Object -First 1
            if ($inPred) { return $inPred.FullName }
            return $cache
        } catch { return '' }
    }
    return ''
}

# Predecessor candidates for a GPF build - same object shape as Get-PredecessorCandidates, but:
#  1. the request's OWN Predecessor\ folder comes FIRST (authoritative - the team has NO live share access);
#  2. the Outgoing scan tolerates the brand prefix + mangled revision in folder names.
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
        if ("$($p.Vendor)_$($p.AppName)" -ine "$($Parsed.Vendor)_$($Parsed.AppName)") { return }
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
    foreach ($root in @($r.VendorSourcesDir, $src, $r.PayloadRoot) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique) {
        foreach ($d in (Get-ChildItem -LiteralPath $root -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -match '(?i)^\.(docx|doc|pdf|txt)$' -and
                                       $_.FullName -notmatch '(?i)[\\/]predecessor[\\/]' -and   # CURRENT request only - never a predecessor's doc
                                       $_.BaseName -match '(?i)install.*instru|instru.*install|installation.*guide|install.?instructions|how.?to.?install' })) {
            if (-not ($docs -contains $d.FullName)) { [void]$docs.Add($d.FullName); [void]$r.Notes.Add("Install instructions found: $($d.Name) (from $((Split-Path $root -Leaf)))") }
        }
    }
    # Final guard: NEVER ship a predecessor's document. Drop any collected item that sits under a "Predecessor" folder
    # (team finding: only the CURRENT request's documents belong in the package's Documents folder).
    $r.DocItems = @($docs | Where-Object { "$_" -notmatch '(?i)[\\/]predecessor[\\/]' })

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