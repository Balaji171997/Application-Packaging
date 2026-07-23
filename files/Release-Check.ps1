##############################################################
# Release-Check.ps1  -  Package Builder RELEASE GATE
# Run before shipping a build:  powershell -ExecutionPolicy Bypass -File .\Release-Check.ps1
# Validates EVERYTHING the tool ships end-to-end:
#   1. every shipped module parses,
#   2. config files are valid JSON,
#   3. the engine + blank v4 template load,
#   4. FRESH + PREDECESSOR-REUSE builders produce parse-clean PSADT v4 across a live-corpus sample,
#   5. the packed PackageBuilder.pak round-trips (AES-256 decrypt -> Deflate -> parse) exactly as the loader runs it.
# Test-Build.ps1 is the UNIT/behaviour gate; this is the broad INTEGRATION/portability gate.
##############################################################
param([int]$Sample = 100, [string]$Root)
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$d = $Root
$fail = 0
function Line($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Check($name, $ok, $detail = '') { if ($ok) { Write-Host ("  [OK]  $name") -ForegroundColor Green } else { Write-Host ("  [X]   $name  $detail") -ForegroundColor Red; $script:fail++ } }

Line "`n=== 1. PARSE every shipped module ===" 'Cyan'
# Required = the runtime packed into the pak (Pack-Engine engineFiles) + GUI + the loader + the maintainer packer.
$required = @('Core.ps1','Theme.ps1','Predecessor.ps1','Build.ps1','Source.ps1','MstBuilder.ps1','BundledMsi.ps1',
              'Snapshot.ps1','Screenshots.ps1','Assemble.ps1','Snippets.ps1','Sccm.ps1','Intune.ps1',
              'PSADT_V3toV4_Mappings.ps1','GUI.ps1','Loader.ps1','Pack-Engine.ps1')
$optional = @('SourceAnalyzer.ps1','Editor.ps1')   # dev helpers - parse if present, not shipped in the pak
foreach ($f in $required) {
    $p = Join-Path $d $f
    if (-not (Test-Path $p)) { Check "$f present" $false '(missing)'; continue }
    $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
    Check "$f parses" ($e.Count -eq 0) $(if ($e.Count) { "L$($e[0].Extent.StartLineNumber): $($e[0].Message)" })
}
foreach ($f in $optional) {
    $p = Join-Path $d $f; if (-not (Test-Path $p)) { continue }
    $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
    Check "$f parses (dev)" ($e.Count -eq 0) $(if ($e.Count) { "L$($e[0].Extent.StartLineNumber): $($e[0].Message)" })
}

Line "`n=== 2. CONFIG files are valid JSON ===" 'Cyan'
foreach ($j in 'settings.json','snippets.json','KnowledgeBase.Recommend.json') {
    $p = Join-Path $d $j
    if (-not (Test-Path $p)) { Check "$j present" $false '(missing)'; continue }
    try { Get-Content $p -Raw | ConvertFrom-Json | Out-Null; Check "$j valid JSON" $true } catch { Check "$j valid JSON" $false $_.Exception.Message }
}

Line "`n=== 3. Load engine + template ===" 'Cyan'
. "$d\Core.ps1"; . "$d\Predecessor.ps1"; . "$d\Build.ps1"; . "$d\Source.ps1"; . "$d\Snippets.ps1"; . "$d\MstBuilder.ps1"; . "$d\PSADT_V3toV4_Mappings.ps1"
Initialize-Config "$d\settings.json" | Out-Null
$tpl = Get-TemplateScript -Root $d
Check "blank v4 template loads" ([bool]$tpl)

Line "`n=== 4. CORPUS: fresh + predecessor-reuse builds parse-clean ===" 'Cyan'
$repo = '\\mbddfsovpc01.mn-man.biz\SWDLive-Gate\CMLib_LIVE\Apps'
function Bump($v) { if ($v -match '^\d+(\.\d+)*$') { $p = $v.Split('.'); $p[-1] = [string]([int]$p[-1] + 1); return ($p -join '.') } return $v }
if (-not (Test-Path $repo)) {
    Line "  (live corpus share not reachable - skipping the corpus gate on this machine)" 'Yellow'
} else {
    $dirs = @(Get-ChildItem -LiteralPath $repo -Directory -EA SilentlyContinue) | Get-Random -Count $Sample
    $nF = 0; $okF = 0; $nR = 0; $okR = 0; $bad = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $dirs) {
        try {
            $m = Read-PredecessorModel -PackagePath $dir.FullName -PackageName $dir.Name; if (-not $m) { continue }
            $id = $m.Identity; $ver = "$($id.Version)"; if (-not $ver) { continue }
            # FRESH build from this identity (synthesise an installer of the predecessor's type)
            $fp = @{ Vendor=$id.Vendor; AppName=$id.AppName; Arch=$id.Arch; Lang=$id.Lang; Revision=$id.Release; Version=$ver; FullName=$id.FullName; Author='RelCheck' }
            if ("$($m.Installer.Type)" -eq 'EXE') { $fp.ExeFileName = 'setup.exe'; $fp.InstallParams = '/S' } else { $fp.MsiFileName = 'app.msi' }
            $bf = Build-FreshScript -NewPkg $fp -Template $tpl
            if ($bf) { $nF++; $e = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($bf, [ref]$null, [ref]$e); if (-not $e.Count) { $okF++ } else { $bad.Add("FRESH:$($dir.Name):$($e[0].Message)") } }
            # REUSE build (retarget to the next version)
            $nv = Bump $ver
            $rp = @{ Vendor=$id.Vendor; AppName=$id.AppName; Arch=$id.Arch; Lang=$id.Lang; Revision=$id.Release; Version=$nv; FullName='x'; ProductCode=$m.Installer.ProductCode; MsiFileName=$m.Installer.MsiFileName; ExeFileName=$m.Installer.ExeFileName; Installers=@() }
            $br = Build-PredecessorScript -Model $m -NewPkg $rp -Template $tpl -AddUninstallPrevious $true
            if ($br) { $nR++; $e = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($br, [ref]$null, [ref]$e); if (-not $e.Count) { $okR++ } else { $bad.Add("REUSE:$($dir.Name):$($e[0].Message)") } }
        } catch { $bad.Add("EXC:$($dir.Name):$($_.Exception.Message)") }
    }
    Check "fresh builds parse-clean ($okF/$nF)"  ($okF -eq $nF -and $nF -gt 0)
    Check "reuse builds parse-clean ($okR/$nR)"  ($okR -eq $nR -and $nR -gt 0)
    if ($bad.Count) { Line "  -- first issues --" 'Yellow'; $bad | Select-Object -First 8 | ForEach-Object { Line "    $_" 'Yellow' } }
}

Line "`n=== 5. PAK round-trip (portable artifact runs) ===" 'Cyan'
$pak = Join-Path $d 'PackageBuilder.pak'
if (-not (Test-Path $pak)) {
    Line "  (no PackageBuilder.pak next to this script - run Pack-Engine.ps1 first)" 'Yellow'
} else {
    try {
        $cipher = [IO.File]::ReadAllBytes($pak)
        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = [Text.Encoding]::UTF8.GetBytes('PB-2026-MTB-EQS-EngineKey-32byte')
        $aes.IV  = [Text.Encoding]::UTF8.GetBytes('PBInitVector16by')
        $plain = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length); $aes.Dispose()
        $ms = New-Object IO.MemoryStream(, $plain)
        $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
        $sr = New-Object IO.StreamReader($ds); $merged = $sr.ReadToEnd(); $sr.Close()
        $e = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($merged, [ref]$null, [ref]$e)
        Check "pak decrypts + decompresses + parses ($([math]::Round($merged.Length/1KB)) KB)" ($e.Count -eq 0) $(if ($e.Count) { "L$($e[0].Extent.StartLineNumber): $($e[0].Message)" })
    } catch { Check "pak round-trip" $false $_.Exception.Message }
}

Line "`n=== RESULT ===" 'Cyan'
if ($fail -eq 0) { Line "RELEASE CHECK PASSED - all gates green." 'Green' } else { Line "RELEASE CHECK: $fail gate(s) FAILED." 'Red'; exit 1 }
