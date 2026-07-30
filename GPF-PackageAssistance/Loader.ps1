##############################################################
# Package Builder - LOADER (compile this ONCE into PackageBuilder.exe with ps2exe:
#   Invoke-PS2EXE -InputFile .\Loader.ps1 -OutputFile .\PackageBuilder.exe -STA -noConsole `
#                 -title 'Package Builder' -iconFile .\Lib\PackageBuilder.ico
# It never changes again - tool updates ship as a new PackageBuilder.pak only.)
#
# What it does:
#   1. finds PackageBuilder.pak next to itself
#   2. (optional) if settings.json has "UpdatePath" and a NEWER .pak exists there, copies it
#      over the local one first -> team always runs the latest engine without redistribution
#   3. decrypts + decompresses the pak in memory and executes it (no script ever on disk)
##############################################################

# Root = the exe's folder when compiled ($PSScriptRoot is empty inside ps2exe), else this script's.
$root = if ($PSScriptRoot) { $PSScriptRoot } else {
    Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

# Running as a plain .ps1 (testing) needs STA for WPF; relaunch once if not.
if (-not $PSScriptRoot) { } # exe build: ps2exe -STA guarantees STA
elseif ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$($MyInvocation.MyCommand.Path)`"")
    return
}

$pak = Join-Path $root 'PackageAssistance.pak'

# Optional self-update from a maintainer share (settings.json -> "UpdatePath").
try {
    $settings = Join-Path $root 'settings.json'
    if (Test-Path $settings) {
        $cfg = (Get-Content $settings -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json
        if ($cfg.UpdatePath) {
            $remote = Join-Path "$($cfg.UpdatePath)" 'PackageAssistance.pak'
            if ((Test-Path $remote) -and (-not (Test-Path $pak) -or
                (Get-Item $remote).LastWriteTimeUtc -gt (Get-Item $pak).LastWriteTimeUtc)) {
                Copy-Item $remote $pak -Force
            }
        }
    }
} catch {}   # update is best-effort; never blocks launch

if (-not (Test-Path $pak)) {
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show("PackageAssistance.pak not found next to the launcher:`n$pak", 'Package Assistance') | Out-Null
    return
}

# Decrypt (AES-256) + decompress (Deflate). Key/IV must match Pack-Engine.ps1.
$cipher = [IO.File]::ReadAllBytes($pak)
$aes = [Security.Cryptography.Aes]::Create()
$aes.Key = [Text.Encoding]::UTF8.GetBytes('PB-2026-MTB-EQS-EngineKey-32byte')
$aes.IV  = [Text.Encoding]::UTF8.GetBytes('PBInitVector16by')
$dec = $aes.CreateDecryptor()
$compressed = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
$aes.Dispose()
$in  = New-Object IO.MemoryStream(,$compressed)
$ds  = New-Object IO.Compression.DeflateStream($in, [IO.Compression.CompressionMode]::Decompress)
$out = New-Object IO.MemoryStream
$ds.CopyTo($out); $ds.Close()
$code = [Text.Encoding]::UTF8.GetString($out.ToArray())

# Execute the tool (the merged source sets $script:PBEngineSource itself for the runspace jobs).
. ([scriptblock]::Create($code))
