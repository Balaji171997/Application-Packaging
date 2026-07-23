##############################################################
# Package Builder - engine packer (MAINTAINER ONLY, never shipped).
# Merges ALL tool .ps1 logic, compresses + encrypts it into ONE binary file:
#     PackageBuilder.pak
# The team runs a small, STABLE loader exe (built once from Loader.ps1) that decrypts and
# executes the pak in memory. UPDATING THE TOOL = run this script, replace the .pak. No
# recompile, no ps2exe, no touching the exe ever again.
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\Pack-Engine.ps1
##############################################################
param([string]$OutFile)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutFile) { $OutFile = Join-Path $root 'PackageBuilder.pak' }

# --- 1. Merge (same model Build-Exe.ps1 proved: engine modules embedded, GUI body verbatim).
$engineFiles = @('Core.ps1','Theme.ps1','Predecessor.ps1','Build.ps1','Source.ps1','MstBuilder.ps1','BundledMsi.ps1',
                 'Snapshot.ps1','Screenshots.ps1','Assemble.ps1','Snippets.ps1','Sccm.ps1','Intune.ps1','BrandGpf.ps1','PSADT_V3toV4_Mappings.ps1')
$sb = New-Object System.Text.StringBuilder
foreach ($f in $engineFiles) {
    $p = Join-Path $root $f
    if (-not (Test-Path $p)) { throw "Engine module missing: $p" }
    [void]$sb.AppendLine("# ===== $f =====")
    [void]$sb.AppendLine(([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)).TrimStart([char]0xFEFF))
    [void]$sb.AppendLine()
}
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sb.ToString()))
$gui = ([IO.File]::ReadAllText((Join-Path $root 'GUI.ps1'), [Text.Encoding]::UTF8)).TrimStart([char]0xFEFF)
$merged = @"
# Package Builder - packed build $(Get-Date -Format 'yyyy-MM-dd HH:mm')
`$script:PBEngineSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))
. ([scriptblock]::Create(`$script:PBEngineSource))
$gui
"@

# --- 2. Parse gate: never pack a broken build.
$tok = $null; $errs = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($merged, [ref]$tok, [ref]$errs)
if ($errs.Count) { throw "Merged source has $($errs.Count) parse error(s) - first: L$($errs[0].Extent.StartLineNumber) $($errs[0].Message)" }

# --- 3. Compress (Deflate) + encrypt (AES-256). Key/IV must match Loader.ps1.
$raw = [Text.Encoding]::UTF8.GetBytes($merged)
$ms  = New-Object IO.MemoryStream
$ds  = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Compress)
$ds.Write($raw, 0, $raw.Length); $ds.Close()
$compressed = $ms.ToArray()

$aes = [Security.Cryptography.Aes]::Create()
$aes.Key = [Text.Encoding]::UTF8.GetBytes('PB-2026-MTB-EQS-EngineKey-32byte')   # 32 bytes
$aes.IV  = [Text.Encoding]::UTF8.GetBytes('PBInitVector16by')                   # 16 bytes
$enc = $aes.CreateEncryptor()
$cipher = $enc.TransformFinalBlock($compressed, 0, $compressed.Length)
$aes.Dispose()

[IO.File]::WriteAllBytes($OutFile, $cipher)
Write-Host ("Packed -> {0}  ({1} KB merged -> {2} KB pak)" -f $OutFile, [math]::Round($raw.Length/1KB), [math]::Round($cipher.Length/1KB)) -ForegroundColor Green
Write-Host 'Deploy: copy this .pak over the team copy (next to PackageBuilder.exe). Nothing else changes.'
