# Phase 3 verification: does SharePoint.ps1 behave when loaded on top of PB's real engine?
# Run the stages one at a time.
#
#   -Stage Off    load + capture check + FEATURE OFF  (no network, no sign-in) - the SAFETY test
#   -Stage Source FEATURE ON  -> Find-SourceFolder returns a SharePoint-staged local path
#   -Stage Pred   FEATURE ON  -> candidates (no download) + lazy materialisation on first read
#
#   .\Test-SharePointModule.ps1 -Stage Off
#   .\Test-SharePointModule.ps1 -Stage Source -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0003_MUL'
#   .\Test-SharePointModule.ps1 -Stage Pred   -PkgName '3Dconnexion_3DxWare_x64_10.9.1.650-0004_MUL'

param(
    [ValidateSet('Off','Source','Pred')][string]$Stage = 'Off',
    [string]$PkgName = '3Dconnexion_3DxWare_x64_10.9.1.650-0003_MUL',
    [string]$PBRoot  = (Join-Path (Split-Path $PSScriptRoot -Parent) 'SP-PackageCompanion')
)

$ErrorActionPreference = 'Continue'

function Say { param([string]$m, [string]$c = 'Gray') Write-Host $m -ForegroundColor $c }
function Pass { param([string]$m) Write-Host "  PASS  $m" -ForegroundColor Green }
function Fail { param([string]$m) Write-Host "  FAIL  $m" -ForegroundColor Red }

# ---- load PB's engine, in the same order GUI.ps1 dot-sources it -------------------------------
$engine = @('Core.ps1','Predecessor.ps1','Build.ps1','Source.ps1','PSADT_V3toV4_Mappings.ps1')
foreach ($m in $engine) {
    $p = Join-Path $PBRoot $m
    if (-not (Test-Path -LiteralPath $p)) { Fail "missing PB module: $p"; return }
    . $p
}
Say "Loaded PB engine: $($engine -join ', ')" 'DarkGray'

# Snapshot the originals BEFORE SharePoint.ps1 replaces them, so we can prove delegation really works.
$preFind = (Get-Command Find-SourceFolder -ErrorAction SilentlyContinue).ScriptBlock
$prePred = (Get-Command Get-PredecessorCandidates -ErrorAction SilentlyContinue).ScriptBlock
$preRead = (Get-Command Read-PredecessorModel -ErrorAction SilentlyContinue).ScriptBlock

# ---- load the SharePoint layer on top (from the SP tool folder - the canonical copy) ----------
. (Join-Path $PBRoot 'SharePoint.ps1')
Say "Loaded SharePoint.ps1 on top (from $PBRoot)." 'DarkGray'

# GUI.ps1 does this at startup. WITHOUT it Get-Setting returns nothing, so PredecessorPath is empty and only
# the hardcoded 2nd repo is ever searched - i.e. the test would exercise a config the real tool never runs in.
Initialize-Config (Join-Path $PBRoot 'settings.json')
Say "Config loaded - PredecessorPath = $(Get-Setting PredecessorPath)" 'DarkGray'

Write-Host "`n=== Stage: $Stage ===" -ForegroundColor Cyan

if ($Stage -eq 'Off') {
    # 1. all three originals captured?
    foreach ($n in @('OrigFindSourceFolder','OrigGetPredecessorCandidates','OrigReadPredecessorModel')) {
        $v = Get-Variable -Name $n -Scope Script -ErrorAction SilentlyContinue
        if ($v -and $v.Value) { Pass "captured `$script:$n" } else { Fail "did NOT capture `$script:$n" }
    }
    # 2. the captured block must be the PRE-override one, not the override itself (else infinite recursion)
    if ($script:OrigFindSourceFolder -and "$($script:OrigFindSourceFolder)" -eq "$preFind") { Pass 'captured Find-SourceFolder is the ORIGINAL body' }
    else { Fail 'captured Find-SourceFolder is NOT the original - recursion risk' }
    if ($script:OrigReadPredecessorModel -and "$($script:OrigReadPredecessorModel)" -eq "$preRead") { Pass 'captured Read-PredecessorModel is the ORIGINAL body' }
    else { Fail 'captured Read-PredecessorModel is NOT the original' }

    # 3. functions really were replaced
    $nowFind = (Get-Command Find-SourceFolder).ScriptBlock
    if ("$nowFind" -ne "$preFind") { Pass 'Find-SourceFolder is now the override' } else { Fail 'override did not take effect' }

    # 4. the CODE default must be off (so dropping SharePoint.ps1 into a tool changes nothing until asked).
    #    This tool's shipped settings.json then deliberately turns it ON - report both, they are different things.
    if (-not $script:SPDefaults.Enabled) { Pass 'code default is OFF (SharePoint.ps1 is inert unless configured)' }
    else { Fail 'code default is ON - unsafe for any tool that drops this file in' }
    Say "      shipped settings.json has Enabled = $((Get-SPConfig).Enabled)  <- intentional for the SP tool" 'DarkGray'

    # 5. with it turned OFF, the overrides must delegate and NEVER touch SharePoint.
    #    Force it off in-memory (settings.json says on) so we are testing the disabled path itself.
    $script:SPKillSwitch = $true
    $script:SPDefaults.Enabled = $false
    $savedSetting = Get-Setting 'SharePoint'
    if ($savedSetting) { $savedSetting.Enabled = $false }
    $script:SPConnected = $false
    $null = Find-SourceFolder -PkgName 'Nonexistent_Thing_x64_1.0.0-0001_MUL'
    if (-not $script:SPConnected) { Pass 'OFF: Find-SourceFolder delegated without connecting to SharePoint' }
    else { Fail 'OFF: it connected to SharePoint anyway' }

    $null = Get-PredecessorCandidates ([pscustomobject]@{ Vendor='X'; AppName='Y'; Version='1.0'; Release='0001'; FullName='X_Y_x64_1.0-0001_MUL' })
    if (-not $script:SPConnected) { Pass 'OFF: Get-PredecessorCandidates delegated without connecting' }
    else { Fail 'OFF: predecessor path connected anyway' }

    Say "`nOFF-mode behaviour is unchanged: with Enabled=false this file is inert." 'Green'
    return
}

# ---- ON modes ---------------------------------------------------------------------------------
$script:SPDefaults.Enabled = $true
Say "Feature switched ON for this test run (in-memory only; settings.json untouched)." 'Yellow'

$parsed = Parse-PackageName $PkgName
if (-not $parsed.IsValid) { Fail "cannot parse '$PkgName'"; return }
Say "Parsed: Vendor=$($parsed.Vendor) App=$($parsed.AppName) Ver=$($parsed.Version) Rel=$($parsed.Release)" 'DarkGray'

if ($Stage -eq 'Source') {
    Say "`nCalling PB's Find-SourceFolder (now SharePoint-backed)..." 'Cyan'
    $path = Find-SourceFolder -PkgName $PkgName
    if (-not $path) { Fail 'no source path returned'; return }
    Pass "returned: $path"
    if (-not (Test-Path -LiteralPath $path)) { Fail 'path does not exist on disk'; return }

    # And the real proof: PB's own Resolve-Source must accept it.
    Say "`nHanding it to PB's Resolve-Source..." 'Cyan'
    $res = Resolve-Source -RootPath $path
    if ($res.Valid -and @($res.Installers).Count -gt 0) {
        Pass "Resolve-Source: Valid=True, Mode=$($res.Mode), $(@($res.Installers).Count) installer(s)"
        @($res.Installers) | ForEach-Object { Say "        $($_.FullName)" 'DarkGray' }
    } else { Fail "Resolve-Source did not find an installer (Valid=$($res.Valid))" }
    return
}

if ($Stage -eq 'Pred') {
    Say "`nCalling PB's Get-PredecessorCandidates (now SharePoint-backed)..." 'Cyan'
    $cands = @(Get-PredecessorCandidates $parsed)
    if (@($cands).Count -eq 0) { Fail 'no candidates returned'; return }
    Pass "$(@($cands).Count) candidate(s), best first:"
    $cands | ForEach-Object {
        Say ("        {0}  score={1} ver={2} rev={3}" -f $_.Name, $_.Score, $_.Version, $_.Revision) 'DarkGray'
    }

    # Nothing should have downloaded yet - the list must be cheap.
    $pick = $cands[0]
    $staged = Test-Path -LiteralPath (Join-Path $pick.FullName '.spcomplete')
    if (-not $staged) { Pass 'candidate list did NOT download anything (lazy, as designed)' }
    else { Say '  note: this predecessor was already staged by an earlier run' 'DarkGray' }

    # Now select it - Read-PredecessorModel should materialise it on first touch.
    Say "`nSelecting '$($pick.Name)' -> Read-PredecessorModel should fetch it now..." 'Cyan'
    $model = Read-PredecessorModel -PackagePath $pick.FullName -PackageName $pick.Name

    if (Test-Path -LiteralPath (Join-Path $pick.FullName '.spcomplete')) { Pass "materialised at $($pick.FullName)" }
    else { Fail 'predecessor was not materialised' }

    Get-ChildItem -LiteralPath $pick.FullName -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { Say ("        {0,8:N1} KB  {1}" -f ($_.Length/1KB), $_.FullName.Substring($pick.FullName.Length+1)) 'DarkGray' }

    if ($model) {
        Pass "Read-PredecessorModel returned a model (TemplateVer=$($model.TemplateVer))"
        if ($model.Identity) { Say "        Identity: $($model.Identity.Vendor) / $($model.Identity.AppName) / $($model.Identity.Version)" 'DarkGray' }
    } else { Fail 'Read-PredecessorModel returned null - check the toolkit script was among the fetched files' }
    return
}
