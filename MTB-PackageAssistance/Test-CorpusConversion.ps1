<#
.SYNOPSIS
  CORPUS CORRUPTION SCANNER. Runs the tool's OWN predecessor-reuse pipeline (Read-PredecessorModel ->
  v3->v4 convert -> boilerplate strip -> Build-PredecessorScript with a version bump) against real packages
  from the live library, and flags where it would produce a BROKEN or CORRUPTED script. This finds the
  systematic weaknesses across every team convention - the corruption class, in bulk, before production hits it.

  Per package it checks the BUILT script for:
    - PARSE errors        (AST) ............. broken script = critical corruption
    - brace/paren balance ................... structural corruption
    - leftover v3 cmdlets ................... incomplete v3->v4 conversion (won't run on v4)
    - lost custom log lines ................. content dropped by the strip (the "deleted Write-ADTLogEntry" class)
    - empty main section .................... a section that had content came out empty

.EXAMPLE
  .\Test-CorpusConversion.ps1 -Sample 120          # fast representative scan
  .\Test-CorpusConversion.ps1 -All                 # every package (slow, thorough)
#>
[CmdletBinding()]
param(
    [int]$Sample = 120,
    [switch]$All,
    [string]$RepoPath = '\\mbddfsovpc01.mn-man.biz\SWDLive-Gate\CMLib_LIVE\Apps',
    [string]$OutCsv
)
$d = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
. "$d\Core.ps1"; . "$d\Predecessor.ps1"; . "$d\Build.ps1"; . "$d\Source.ps1"; . "$d\Snippets.ps1"
. "$d\MstBuilder.ps1"; . "$d\PSADT_V3toV4_Mappings.ps1"
Initialize-Config "$d\settings.json" | Out-Null
$tpl = Get-TemplateScript -Root $d
if (-not $tpl) { Write-Host "No blank template found - cannot test the build." -ForegroundColor Red; return }

# v3-only cmdlets that MUST be converted to v4 (if present in the built v4 script = conversion gap).
$v3Only = 'Execute-Process','Execute-MSI','Execute-MSP','Show-InstallationWelcome','Show-InstallationProgress',
          'Show-InstallationPrompt','Show-InstallationRestartPrompt','Set-RegistryKey','Remove-RegistryKey',
          'Get-RegistryKey','Copy-File','Remove-File','Remove-Folder','New-Folder','Get-LoggedOnUser',
          'Refresh-Desktop','Update-Desktop','Execute-ProcessAsUser','Get-InstalledApplication','Get-FileVersion',
          'Set-ActiveSetup','Get-ScheduledTask','Test-Battery','Block-AppExecution'
$v3Re = '\b(' + (($v3Only | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'

function Bump-Version { param([string]$v) if ($v -match '^\d+(\.\d+)*$') { $p=$v.Split('.'); $p[-1]=[string]([int]$p[-1]+1); return ($p -join '.') } return $v }
function BraceDelta { param([string]$t) $s=[regex]::Replace($t,"'[^']*'",''); $s=[regex]::Replace($s,'"[^"]*"',''); ([regex]::Matches($s,'\{')).Count - ([regex]::Matches($s,'\}')).Count }

$dirs = @(Get-ChildItem -LiteralPath $RepoPath -Directory -ErrorAction SilentlyContinue)
if (-not $All) { $dirs = $dirs | Get-Random -Count ([Math]::Min($Sample, $dirs.Count)) }
Write-Host "Corruption-scanning $($dirs.Count) package(s) through the build pipeline..." -ForegroundColor Cyan

$results = New-Object System.Collections.Generic.List[object]
$n=0; $sw=[Diagnostics.Stopwatch]::StartNew()
foreach ($dir in $dirs) {
    $n++; if ($n % 10 -eq 0 -or $n -eq $dirs.Count) { Write-Progress -Activity 'Corpus scan' -Status "$n/$($dirs.Count) $($dir.Name)" -PercentComplete ([int](100*$n/$dirs.Count)) }
    $name = $dir.Name
    $rec = [ordered]@{ Package=$name; Template=''; ReadOk=$false; BuildOk=$false; ParseErrors=-1; BraceDelta=0; V3Residue=0; LogLoss=0; EmptySection=''; Note='' }
    try {
        $model = Read-PredecessorModel -PackagePath $dir.FullName
        if (-not $model) { $rec.Note='no model'; $results.Add([pscustomobject]$rec); continue }
        $rec.ReadOk=$true; $rec.Template=$model.TemplateVer
        $id = $model.Identity
        $newPkg = @{ Vendor=$id.Vendor; AppName=$id.AppName; Arch=$id.Arch; Lang=$id.Lang; Revision=$id.Release
                     Version=(Bump-Version $id.Version); FullName="$($id.Vendor)_$($id.AppName)_$($id.Arch)_$(Bump-Version $id.Version)-$($id.Release)_$($id.Lang)"
                     ProductCode=$model.Installer.ProductCode; Ritm='RITMTEST'; Author='Test'
                     MsiFileName=$model.Installer.MsiFileName; ExeFileName=$model.Installer.ExeFileName }
        $built = Build-PredecessorScript -Model $model -NewPkg $newPkg -Template $tpl -AddUninstallPrevious $false
        if (-not $built) { $rec.Note='build returned empty'; $results.Add([pscustomobject]$rec); continue }
        $rec.BuildOk=$true
        $errs=$null; [void][System.Management.Automation.Language.Parser]::ParseInput($built,[ref]$null,[ref]$errs)
        $rec.ParseErrors = $errs.Count
        $rec.BraceDelta  = BraceDelta $built
        $rec.V3Residue   = ([regex]::Matches($built, $v3Re)).Count
        # content loss: custom log lines (those NOT matching template scaffolding wording)
        $predLogs = @([regex]::Matches(($model.Code.Values -join "`n"), '(?i)Write-(ADT)?LogEntry')).Count
        $builtLogs= @([regex]::Matches($built, '(?i)Write-(ADT)?LogEntry')).Count
        if ($predLogs -gt 0 -and $builtLogs -lt $predLogs) { $rec.LogLoss = $predLogs - $builtLogs }
        # empty main section that had content in the model
        foreach ($s in 'MainInstallCode','MainUninstallCode') {
            $body = "$($model.Code.$s)"
            if ($body.Trim() -and ($built -notmatch [regex]::Escape(($body.Trim() -split "\r?\n" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | Select-Object -First 1)))) { $rec.EmptySection = $s; break }
        }
    } catch { $rec.Note = "EXCEPTION: $($_.Exception.Message)" }
    $results.Add([pscustomobject]$rec)
}
Write-Progress -Activity 'Corpus scan' -Completed; $sw.Stop()

# ---- report ----
$built  = @($results | Where-Object BuildOk)
$broken = @($built | Where-Object { $_.ParseErrors -gt 0 })
$brace  = @($built | Where-Object { $_.BraceDelta -ne 0 })
$v3res  = @($built | Where-Object { $_.V3Residue -gt 0 })
$logloss= @($built | Where-Object { $_.LogLoss -gt 0 })
$empty  = @($built | Where-Object { $_.EmptySection })
$exc    = @($results | Where-Object { $_.Note -like 'EXCEPTION*' })
Write-Host ""
Write-Host "===== CORPUS CORRUPTION SCAN ($($results.Count) packages, $([math]::Round($sw.Elapsed.TotalMinutes,1)) min) =====" -ForegroundColor Cyan
Write-Host ("built ok           : {0}/{1}" -f $built.Count, $results.Count)
Write-Host ("PARSE ERRORS       : {0}   <- broken scripts (critical)" -f $broken.Count) -ForegroundColor $(if($broken.Count){'Red'}else{'Green'})
Write-Host ("brace imbalance    : {0}" -f $brace.Count) -ForegroundColor $(if($brace.Count){'Red'}else{'Green'})
Write-Host ("v3 residue (gap)   : {0}   <- v3 cmdlets left in the v4 script" -f $v3res.Count) -ForegroundColor $(if($v3res.Count){'Yellow'}else{'Green'})
Write-Host ("custom-log loss    : {0}   <- dropped Write-ADTLogEntry lines" -f $logloss.Count) -ForegroundColor $(if($logloss.Count){'Yellow'}else{'Green'})
Write-Host ("empty main section : {0}" -f $empty.Count) -ForegroundColor $(if($empty.Count){'Yellow'}else{'Green'})
Write-Host ("build EXCEPTIONS   : {0}" -f $exc.Count) -ForegroundColor $(if($exc.Count){'Red'}else{'Green'})
if ($broken.Count) { Write-Host "`n-- parse failures (sample) --" -ForegroundColor Red; $broken | Select-Object -First 10 | ForEach-Object { "  $($_.Package)  ($($_.Template), $($_.ParseErrors) err, braceDelta $($_.BraceDelta))" } }
if ($v3res.Count) { Write-Host "`n-- v3 residue (sample) --" -ForegroundColor Yellow; $v3res | Sort-Object V3Residue -Descending | Select-Object -First 10 | ForEach-Object { "  $($_.Package)  ($($_.V3Residue) v3 cmdlets)" } }
if ($logloss.Count){ Write-Host "`n-- custom-log loss (sample) --" -ForegroundColor Yellow; $logloss | Sort-Object LogLoss -Descending | Select-Object -First 10 | ForEach-Object { "  $($_.Package)  (-$($_.LogLoss) log lines)" } }
if ($exc.Count)   { Write-Host "`n-- exceptions (sample) --" -ForegroundColor Red; $exc | Select-Object -First 8 | ForEach-Object { "  $($_.Package): $($_.Note)" } }
if (-not $OutCsv) { $OutCsv = Join-Path $d 'CorpusScan.csv' }
$results | Export-Csv -NoTypeInformation -Path $OutCsv -Encoding utf8
Write-Host "`nfull results -> $OutCsv" -ForegroundColor Green
