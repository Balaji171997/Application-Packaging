##############################################################
# Snapshot.ps1
# "What did this installer do?" - capture the machine's install-relevant surface, diff a BEFORE vs AFTER a run,
# and categorise the result in plain language. Sandbox-INDEPENDENT: runs on the current machine with a manual
# trigger (user runs the installer between the two snapshots); a sandbox can drive it automatically later.
#
# Categories: Programs (Uninstall entries) - the detection + UNINSTALL command come from here; Services;
# Scheduled tasks; Run keys (autostart); Shortcuts; Certificates; Drivers; Printers; Program folders; Fonts.
# Each capture is fast + best-effort (a missing cmdlet never breaks the whole snapshot).
##############################################################

# Plain-language guidance shown on the Testing/Snapshot tab so a beginner knows WHETHER they even need a snapshot and
# WHAT happens - it differs by installer type and whether a predecessor is being reused:
#   * Predecessor reuse -> the tool carries the predecessor's proven uninstall + settings; a snapshot is usually NOT needed.
#   * MSI -> uninstall is automatic (product code) and settings ride in the MST; anything the MST can't do safely (extra
#            leftovers, or a risky change like a shared run-key) is handled in the PSADT script. Snapshot is OPTIONAL.
#   * EXE -> no product code / no MST, so a snapshot is RECOMMENDED (it finds the real uninstall + what to detect/clean,
#            applied via the PSADT script).
# Always the same 3 steps when you DO run it: 1) Take baseline  2) install the app  3) Analyze.
function Get-SnapshotGuidance {
    param([string]$InstallerPath, [bool]$HasPredecessor)
    $steps = 'Steps: 1) Take baseline  2) install the app  3) Analyze.'
    if ($HasPredecessor) {
        return "Predecessor loaded: the tool reuses its proven uninstall + settings, so a snapshot is usually NOT needed - run one only to double-check leftovers. $steps"
    }
    switch ([IO.Path]::GetExtension("$InstallerPath").ToLower()) {
        '.msi' { return "MSI package: uninstall is automatic (product code) and settings ride in the MST; extra leftovers or risky changes (e.g. a shared run-key) go into the PSADT script. A snapshot is OPTIONAL - only to catch leftovers. $steps" }
        '.msp' { return "MSP patch: applied via msiexec. A snapshot is OPTIONAL (leftovers only). $steps" }
        '.exe' { return "EXE installer (no product code): a snapshot is RECOMMENDED - it's how the tool learns the real uninstall + what to detect/clean (applied via the PSADT script). $steps" }
        default { return "A snapshot captures what an install changes so the tool can build detection + cleanup. Nothing scans until you click Take baseline. $steps" }
    }
}

# Background/OS noise tokens - things that change on ANY machine regardless of the app being packaged. Filtered
# from the diff ONLY when they don't match the app's own vendor/name (see Test-IsSnapshotNoise), so a Citrix app
# still shows Citrix changes, a McAfee app shows McAfee, etc. Nothing is deleted - noise just collapses.
$script:SnapshotNoise = @(
    'microsoft ','windows ','windows defender','defender','msedge','microsoft edge','edge update','edgeupdate',
    'onedrive','google update','googleupdate','google chrome','intel(r)','nvidia','realtek','amd ',
    'mcafee','trellix','crowdstrike','sentinel','symantec','configuration manager','configmgr','ccmexec','sccm',
    'citrix','vmware','zscaler','tanium','qualys','splunk','bigfix','tenable','forcepoint',
    'visual c++','vcredist','redistributable','webview2','teams machine-wide','microsoft .net','dotnet',
    'kb[0-9]','security update','update for microsoft'
)
function Test-IsSnapshotNoise {
    param([string]$Text, [string[]]$AppTokens)
    if (-not $Text) { return $false }
    $t = $Text.ToLower()
    foreach ($a in @($AppTokens)) { if ($a -and $t.Contains($a)) { return $false } }   # the app's OWN -> never noise
    foreach ($n in $script:SnapshotNoise) { if ($t -match [regex]::Escape($n) -or $t -like "*$n*") { return $true } }
    return $false
}

# ---- DEEP capture, focused on the MAIN install locations (not a whole-disk scan). Goal: cover everything an
# installer realistically writes while keeping a capture to ~1 min - "main things, ignore the junk". Pure churn is
# additionally routed to a collapsed NOISE group at DIFF time.

# All fixed drive roots (kept for reference / a future "deep" toggle; the default capture uses the focused roots).
function Get-FixedDriveRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    try { foreach ($dr in [IO.DriveInfo]::GetDrives()) { if ("$($dr.DriveType)" -eq 'Fixed' -and $dr.IsReady) { $roots.Add($dr.RootDirectory.FullName) } } } catch {}
    if (-not $roots.Count) { $roots.Add('C:\') }
    return $roots.ToArray()
}
# COMPLETE file coverage (SysTracer-style): scan EVERY fixed drive from its root, so an install dir ANYWHERE
# (D:\Apps, C:\Tools, a vendor's odd location, a DLL dropped in System32) is caught - not just the standard
# Program Files paths. Speed does NOT come from a narrow root list; it comes from PRUNING the OS-churn
# megafolders in Get-PathMap (WinSxS / servicing / Windows Update / DriverStore / caches) that installers never
# write to. The before/after DIFF + the noise filter then keep only the real, meaningful changes - junk is never
# stored. "Miss nothing, store no junk." (A genuinely huge data drive is bounded by the time cap, which logs a
# warning if it ever trips so a truncated scan is never silent.)
$script:SnapshotFileRoots = @()
try {
    $script:SnapshotFileRoots = @([IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq [IO.DriveType]::Fixed -and $_.IsReady } |
        ForEach-Object { $_.RootDirectory.FullName })
} catch {}
if (-not $script:SnapshotFileRoots -or @($script:SnapshotFileRoots).Count -eq 0) {
    $script:SnapshotFileRoots = @(($env:SystemDrive + '\'))
}
# Registry hives that carry the install footprint, WITH value-change detection. The huge SOFTWARE\Classes COM/
# file-association store is PRUNED entirely - it dominated the time and is rarely the packaging concern ("ignore
# the junk"). Services are captured separately via CIM, so they're covered regardless.
# (SYSTEM\CurrentControlSet dropped: it's dominated by device Enum noise; new services are already captured via
#  CIM, and machine env via Get-EnvSnapshot - so SOFTWARE is the app footprint that's left.)
$script:SnapshotRegRoots = @('HKLM\SOFTWARE', 'HKCU\SOFTWARE')
$script:SnapshotRegPrune = '(?i)\\SOFTWARE(\\WOW6432Node)?\\Classes(\\|$)'
# OS file churn routed to NOISE at diff time (a second safety net on top of the focused roots).
$script:SnapshotFileNoiseRe = '(?i)\\!{3,}\d+|\\\$Recycle\.Bin\\|\\System Volume Information\\|\\Temp\\|\\Temporary Internet|\\INetCache\\|\\WebCache\\|\\WER\\|\\CrashDumps\\|\\Crashpad\\|\\Microsoft\\Windows\\Caches\\|\\AppData\\Local\\Packages\\|\\catroot2\\|\\wbem\\Repository\\|\\appcompat\\|\\Recent\\|\\Cache2?\\|\\GPUCache\\|\\Code Cache\\|\\Service Worker\\|\\CacheStorage\\|\\WinSxS\\|\\servicing\\|\\SoftwareDistribution\\|\\DriverStore\\|\\Windows\\INF\\|\\Panther\\|\\assembly\\(NativeImages|temp)|\\\$Windows\.~(BT|WS)\\|\\(pagefile|hiberfil|swapfile)\.sys$|\.(log|etl|tmp|evtx|dmp|old|bak|pf|pnf|wal|shm|ldb|crdownload)$'
function Test-IsFileNoise { param([string]$Path) return [bool]("$Path" -match $script:SnapshotFileNoiseRe) }
# Bundled PREREQUISITE / runtime files (VC++ / .NET / WebView2 / UCRT) an installer drops - these ARE part of the
# install even though they live under a Microsoft/vendor path, so a NEW one is KEPT (shown as a prerequisite) rather
# than hidden as vendor noise. Deliberately narrow (runtime dll/redist names), so a browser/AV auto-update stays noise.
$script:SnapshotPrereqRe = '(?i)vcruntime\d|msvcp\d|msvcr\d|concrt\d|vccorlib\d|vcredist|\\Microsoft Visual C\+\+|\\VC\\redist|\\dotnet\\|dotnet\.exe|hostfxr|\\Microsoft\.NET\\|WebView2|ucrtbase|\\api-ms-win-'
function Test-IsPrereqFile { param([string]$Path) return [bool]("$Path" -match $script:SnapshotPrereqRe) }
# Registry keys that churn regardless of installs (MRU / telemetry / usage) -> NOISE at diff time.
$script:SnapshotRegNoiseRe = '(?i)\\(MuiCache|UsageData|Notifications|TraceLogging|Diagnostics|Telemetry|EventTranscript|BAM|DAM|StateRepository|CloudStore|RecentDocs|TypedURLs|ComDlg32|UserAssist|FeatureUsage|BgTaskRegistry|AppCompatFlags\\(CIT|Compatibility|MUI))(\\|$)'
function Test-IsRegNoise { param([string]$Key) return [bool]("$Key" -match $script:SnapshotRegNoiseRe) }
# Background / OS / 3rd-party vendor folders+keys that churn on ANY machine (the "exclusion list" pro repackagers
# ship). Filtered from the file/registry diff UNLESS the app being packaged IS that vendor (context-aware via the
# app tokens) - so packaging McAfee shows McAfee, but packaging app X hides McAfee's constant background writes.
$script:SnapshotBgVendors = @(
    '\microsoft','\windows defender','\windows kits','\windowsapps','\windowspowershell','common files\microsoft','\microsoft shared',
    'msedge','edgeupdate','\onedrive','\google\','\mozilla','\intel\','\nvidia','\realtek','\adobe\arm',
    '\mcafee','\trellix','\crowdstrike','\sentinel','\symantec','\sophos','\eset','\kaspersky','\bitdefender','\cylance','\cortex','\cyvera','\traps','\paloalto','\tanium','\qualys','\zscaler','\citrix','\vmware','\splunk','\bigfix','\nessus','\forcepoint',
    '\teams','\office','\dropbox','\zoom','\webex','\slack','\java\','oracle\java','\dotnet\','\packages\plugins',
    'configuration manager','\ccm\','windowsupdate','deliveryoptimization','\wpsystem','\windowsazure','\packagecache'
)
function Test-IsVendorNoise {
    param([string]$Text, [string[]]$AppTokens)
    $t = "$Text".ToLower()
    foreach ($a in @($AppTokens)) { if ($a -and $a.Length -ge 3 -and $t.Contains($a)) { return $false } }   # app's OWN -> keep
    foreach ($v in $script:SnapshotBgVendors) { if ($t.Contains($v)) { return $true } }
    return $false
}
# Does this path/key clearly belong to the app being packaged? (used to surface the app's OWN footprint prominently)
function Test-IsAppItem {
    param([string]$Text, [string[]]$AppTokens)
    $t = "$Text".ToLower()
    foreach ($a in @($AppTokens)) { if ($a -and $a.Length -ge 3 -and $t.Contains($a)) { return $true } }
    return $false
}
# Build the app-match tokens used by Test-IsAppItem / Test-IsVendorNoise. Returns the vendor + the app name AND each
# significant WORD of them (lowercased; >=3 chars; pure version/number + arch/lang words dropped). Using the words -
# not just the whole multi-word string - means a file buried under "...\SMT\MASTA 15.1.8 RLM\...\google\protobuf\..."
# still matches 'masta'/'smt'/'rlm' and is therefore NEVER mis-filed as 3rd-party vendor noise. The user's rule:
# anything carrying the app's own name IS a real change and must always show, even if a deeper folder is a 3rd-party
# runtime (bundled Python/Google/Java/etc.).
$script:AppTokenStop = @('the','and','for','of','x64','x86','x86_64','arm64','win','win32','win64','mul','all','msi','exe','setup','install')
function Get-AppMatchTokens {
    param([string]$Vendor, [string]$AppName)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($Vendor, $AppName)) {
        $s = "$s".Trim(); if (-not $s) { continue }
        $whole = $s.ToLower()
        if ($whole.Length -ge 3 -and -not $out.Contains($whole)) { $out.Add($whole) }   # keep the whole field (contiguous match)
        foreach ($w in ([regex]::Split($whole, '[^a-z0-9]+'))) {
            $w = "$w".Trim()
            if ($w.Length -lt 3) { continue }
            if ($w -match '^\d+([.,]\d+)*$') { continue }      # pure version / number, e.g. 15, 1.8
            if ($script:AppTokenStop -contains $w) { continue }
            if (-not $out.Contains($w)) { $out.Add($w) }
        }
    }
    return $out.ToArray()
}
# Like Get-AppMatchTokens but ALSO learns the app's real identity FROM THE SNAPSHOT: the names of the folders the
# install created (under Program Files / ProgramData) and the app's registered (ARP) DisplayName. This makes the
# "is this the app?" test work even when the PACKAGE name doesn't match the install folder (e.g. package "SMT_MASTA"
# but it installs to "...\SMT\MASTA 15.1.8 RLM" with bundled Python/Google libs) - everything under the app's own
# created folders / matching its ARP name is ALWAYS kept as a real change, never filed as 3rd-party vendor noise.
function Get-SnapshotAppTokens {
    param([string]$Vendor, [string]$AppName, $Diff)
    $toks = New-Object System.Collections.Generic.List[string]
    foreach ($t in (Get-AppMatchTokens -Vendor $Vendor -AppName $AppName)) { if (-not $toks.Contains($t)) { $toks.Add($t) } }
    $addWords = {
        param($text)
        foreach ($w in ([regex]::Split("$text".ToLower(), '[^a-z0-9]+'))) {
            $w = "$w".Trim()
            if ($w.Length -ge 3 -and $w -notmatch '^\d+([.,]\d+)*$' -and ($script:AppTokenStop -notcontains $w) -and (-not $toks.Contains($w))) { $toks.Add($w) }
        }
    }
    if ($Diff) {
        foreach ($d in @($Diff.ProgramDirs.Added)) { & $addWords "$($d.Info.Name)" }      # folder(s) the install CREATED
        foreach ($p in @($Diff.Programs.Added))    { & $addWords "$($p.Info.DisplayName)" }  # the app's ARP DisplayName
    }
    return $toks.ToArray()
}

# Recursive FILE walk -> Dictionary[fullpath] = "length|mtimeTicks", so the diff catches NEW *and* MODIFIED files.
# DirectoryInfo.EnumerateFiles gives size+mtime for free (no extra stat). Per-dir try/catch so one denied folder
# doesn't abort the walk. CRITICAL: reparse points (junctions/symlinks) are SKIPPED - Windows has self-referential
# junctions (e.g. C:\ProgramData\Application Data -> C:\ProgramData) that would otherwise loop FOREVER. A wall-clock
# cap is a final safety net. Only $Recycle.Bin / SVI / recovery dirs are skipped by name.
function Get-PathMap {
    param([string[]]$Roots, [int]$MaxFiles = 5000000, [int]$MaxSeconds = 900)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    # PRUNE the OS-churn megafolders (installers NEVER write here) + pure cache/temp dirs - this is what keeps a
    # whole-drive scan fast. Matched on the folder NAME at any depth. WinSxS / servicing / SoftwareDistribution /
    # DriverStore / Windows-upgrade staging are the big time sinks; drivers + services are captured separately
    # (CIM) regardless, so pruning them loses no real footprint.
    $skipDir = '(?i)^(\$Recycle\.Bin|System Volume Information|\$WinREAgent|\$SysReset|\$GetCurrent|\$Windows\.~BT|\$Windows\.~WS|Recovery|Config\.Msi|WinSxS|servicing|SoftwareDistribution|DriverStore|CbsTemp|Panther|LiveKernelReports|Minidump|Downloaded Program Files|Temp|Cache|Cache2|Caches|INetCache|GPUCache|Code Cache|ScriptCache|Service Worker|CacheStorage|Crashpad|CrashDumps|WER|Prefetch|WebCache|Temporary Internet Files)$'
    $reparse = [IO.FileAttributes]::ReparsePoint
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $stack = New-Object System.Collections.Generic.Stack[string]
    foreach ($r in (@($Roots) | Select-Object -Unique)) { if ($r -and (Test-Path -LiteralPath $r -EA SilentlyContinue)) { $stack.Push($r) } }
    while ($stack.Count -gt 0 -and $map.Count -lt $MaxFiles -and $sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
        $dir = $stack.Pop()
        try {
            $di = [IO.DirectoryInfo]::new($dir)
            foreach ($f in $di.EnumerateFiles())       { $map[$f.FullName] = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)" }
            foreach ($d in $di.EnumerateDirectories())  {
                if (($d.Attributes -band $reparse) -ne 0) { continue }    # junction/symlink -> never descend (loop guard)
                if ($d.Name -notmatch $skipDir) { $stack.Push($d.FullName) }
            }
        } catch {}
    }
    # If we stopped with folders still queued, the map is TRUNCATED -> the before/after diff could show false
    # add/delete. The caps are deliberately generous so this is rare; warn LOUDLY rather than emit a silent,
    # unreliable snapshot (raise MaxSeconds or narrow the roots if a machine is genuinely enormous).
    if ($stack.Count -gt 0) { $script:SnapshotIncomplete = $true; try { Write-Log "Snapshot file scan stopped at a limit (>$MaxSeconds s or >$MaxFiles files) with $($stack.Count) folder(s) unscanned - this snapshot may be INCOMPLETE; results could show false changes." Warning } catch {} }
    return $map
}
# Recursive REGISTRY walk -> Dictionary[keypath] = value-signature ("count:len:hash"), so the diff catches NEW keys
# AND value changes (PATH/env/config) in existing keys. Under Classes/HKCR we record the KEY but skip reading its
# values (sig='K') - reading every COM value is prohibitively slow and not the packaging concern.
function Get-RegMap {
    param([string[]]$Roots, [int]$MaxKeys = 2500000, [int]$MaxDepth = 28, [int]$MaxSeconds = 600, [switch]$ValuesToo)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $truncated = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($root in @($Roots)) {
        $parts = "$root".Split('\', 2)
        $hive = switch ($parts[0]) {
            'HKLM' { [Microsoft.Win32.Registry]::LocalMachine } 'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
            'HKCR' { [Microsoft.Win32.Registry]::ClassesRoot }  'HKU'  { [Microsoft.Win32.Registry]::Users } default { $null } }
        if (-not $hive) { continue }
        $sub = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $stack = New-Object System.Collections.Generic.Stack[object]
        try { $rk = if ($sub) { $hive.OpenSubKey($sub) } else { $hive }; if ($rk) { $stack.Push([pscustomobject]@{ Key=$rk; Path=$root; Depth=0 }) } } catch {}
        while ($stack.Count -gt 0 -and $map.Count -lt $MaxKeys -and $sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
            $cur = $stack.Pop()
            if ($ValuesToo) {
                # Store the ACTUAL values (capped) - name<SOH>type<SOH>value<STX>... - so the diff shows per-value
                # added/removed/CHANGED (old->new), not just "the key changed". Caps bound memory on a broad walk.
                $sb = New-Object System.Text.StringBuilder; $vc = 0
                try { foreach ($vn in $cur.Key.GetValueNames()) {
                        if ($vc -ge 60 -or $sb.Length -gt 6000) { break }
                        $val = "$($cur.Key.GetValue($vn,''))"; if ($val.Length -gt 400) { $val = $val.Substring(0,400) }
                        $val = $val -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ' '
                        [void]$sb.Append($vn).Append([char]1).Append("$($cur.Key.GetValueKind($vn))").Append([char]1).Append($val).Append([char]2); $vc++
                } } catch {}
                $map[$cur.Path] = $sb.ToString()
            } else { $map[$cur.Path] = '1' }   # key-presence only (fast) - detects NEW keys; env value changes covered separately
            if ($cur.Depth -lt $MaxDepth) {
                $names = $null; try { $names = $cur.Key.GetSubKeyNames() } catch {}
                foreach ($n in @($names)) {
                    $cp = "$($cur.Path)\$n"
                    if ($cp -match $script:SnapshotRegPrune) { continue }   # skip the Classes/COM subtree entirely (junk + slow)
                    try { $sk = $cur.Key.OpenSubKey($n); if ($sk) { $stack.Push([pscustomobject]@{ Key=$sk; Path=$cp; Depth=$cur.Depth+1 }) } } catch {}
                }
            }
            try { if ($cur.Depth -gt 0) { $cur.Key.Close() } } catch {}
        }
        if ($stack.Count -gt 0) { $truncated = $true }   # cap hit before this hive finished
    }
    # Same truncation guard as the file scan: a capped registry walk would diff as false add/delete. Warn loudly.
    if ($truncated) { $script:SnapshotIncomplete = $true; try { Write-Log "Snapshot registry scan stopped at a limit (>$MaxSeconds s or >$MaxKeys keys) - this snapshot may be INCOMPLETE; results could show false changes." Warning } catch {} }
    return $map
}
# Environment variables (machine + user) -> @{ "MACHINE\Name"=value; "USER\Name"=value }. Diffed for value changes
# (PATH edits are the canonical installer change the key-only registry diff would otherwise miss in plain text).
function Get-EnvSnapshot {
    $env = @{}
    foreach ($pair in @(@{Scope='MACHINE';Key='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'}, @{Scope='USER';Key='HKCU:\Environment'})) {
        try { $ip = Get-ItemProperty -LiteralPath $pair.Key -ErrorAction SilentlyContinue
              if ($ip) { foreach ($p in $ip.PSObject.Properties) { if ($p.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$') { $env["$($pair.Scope)\$($p.Name)"] = "$($p.Value)" } } } } catch {}
    }
    return $env
}

# Read a registry container's immediate subkeys -> @{ subkeyPath = @{ value=data ... } } (best-effort, no throw).
function Read-RegContainer {
    param([string]$Path, [string[]]$Values)
    $out = @{}
    try {
        Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object {
            $props = @{}
            $ip = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            foreach ($v in @($Values)) { if ($ip.PSObject.Properties.Name -contains $v) { $props[$v] = "$($ip.$v)" } }
            $out[$_.PSChildName] = $props
        }
    } catch {}
    return $out
}
# Flat value list of a single registry key -> @{ valueName = data } (for Run / RunOnce).
function Read-RegValues {
    param([string]$Path)
    $out = @{}
    try {
        $ip = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($ip) { foreach ($pr in $ip.PSObject.Properties) { if ($pr.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$') { $out[$pr.Name] = "$($pr.Value)" } } }
    } catch {}
    return $out
}

# Capture the machine's install-relevant surface. Each category -> a hashtable keyed by a stable id, so the diff
# is a simple key-set comparison. Fast (a few seconds): targeted surfaces, NOT a full disk/registry walk.
function Get-MachineSnapshot {
    param([switch]$NoDeep)   # -NoDeep skips the file/registry tree walk (faster; for unit tests)
    $s = [ordered]@{}
    # PROGRAMS (Uninstall entries) - the richest source: detection name/version/publisher + the UNINSTALL command.
    $uninst = @{}
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                       'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($kv in (Read-RegContainer -Path $root -Values 'DisplayName','DisplayVersion','Publisher','UninstallString','QuietUninstallString','SystemComponent').GetEnumerator()) {
            $id = "$root\$($kv.Key)"
            $kv.Value['_key'] = $kv.Key; $kv.Value['_root'] = $root
            $uninst[$id] = $kv.Value
        }
    }
    $s.Programs = $uninst
    # SERVICES (name -> displayname + image path; image path catches auto-update services).
    $svc = @{}
    try { Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object { $svc[$_.Name] = @{ DisplayName="$($_.DisplayName)"; Path="$($_.PathName)"; Start="$($_.StartMode)"; State="$($_.State)"; Account="$($_.StartName)"; Type="$($_.ServiceType)"; Description="$($_.Description)" } } } catch {}
    $s.Services = $svc
    # SCHEDULED TASKS (path\name -> action / triggers / author) - auto-update tasks live here.
    $tasks = @{}
    try { Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $act = try { (@($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) | Where-Object { $_ }) -join ' ; ' } catch { '' }
            $trg = try { (@($_.Triggers | ForEach-Object { "$($_.CimClass.CimClassName)" -replace '^MSFT_Task','' -replace 'Trigger$','' }) | Where-Object { $_ }) -join ', ' } catch { '' }
            $tasks["$($_.TaskPath)$($_.TaskName)"] = @{ Name="$($_.TaskName)"; Path="$($_.TaskPath)"; Action="$act"; Triggers="$trg"; Author="$($_.Author)"; State="$($_.State)" }
    } } catch {}
    $s.Tasks = $tasks
    # RUN KEYS (autostart).
    $run = @{}
    foreach ($rk in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce') {
        foreach ($kv in (Read-RegValues -Path $rk).GetEnumerator()) { $run["$rk!$($kv.Key)"] = @{ Name=$kv.Key; Command=$kv.Value; Hive=$rk } }
    }
    $s.RunKeys = $run
    # SHORTCUTS (desktop + start menu, machine + user). Use GetFolderPath so OneDrive/Known-Folder REDIRECTION is
    # handled (a redirected Desktop is NOT %USERPROFILE%\Desktop) - that was why desktop shortcuts were missed.
    $sc = @{}
    $scDirs = New-Object System.Collections.Generic.List[string]
    foreach ($kf in 'Desktop','CommonDesktopDirectory','StartMenu','CommonStartMenu','Programs','CommonPrograms') {
        try { $p = [Environment]::GetFolderPath($kf); if ($p) { $scDirs.Add($p) } } catch {}
    }
    foreach ($p in @($env:PUBLIC + '\Desktop', $env:USERPROFILE + '\Desktop', $env:OneDrive + '\Desktop', $env:ProgramData + '\Microsoft\Windows\Start Menu\Programs', $env:APPDATA + '\Microsoft\Windows\Start Menu\Programs')) { $scDirs.Add($p) }
    # Resolve each .lnk's TARGET (+ arguments) so the report shows what a shortcut actually launches, not just its name.
    $wsh = try { New-Object -ComObject WScript.Shell } catch { $null }
    foreach ($d in ($scDirs | Select-Object -Unique)) {
        try { Get-ChildItem -LiteralPath $d -Filter *.lnk -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $tgt=''; $arg=''; if ($wsh) { try { $lk=$wsh.CreateShortcut($_.FullName); $tgt="$($lk.TargetPath)"; $arg="$($lk.Arguments)" } catch {} }
            $sc[$_.FullName] = @{ Name=$_.BaseName; Target=$tgt; Arguments=$arg }
        } } catch {}
    }
    if ($wsh) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) } catch {} }
    $s.Shortcuts = $sc
    # CERTIFICATES (machine trust stores) - subject / issuer / thumbprint / expiry so the packager sees the full cert.
    $certs = @{}
    foreach ($store in 'Root','CA','TrustedPublisher','My','AuthRoot') {
        try { Get-ChildItem -Path "Cert:\LocalMachine\$store" -ErrorAction SilentlyContinue | ForEach-Object { $certs["$store\$($_.Thumbprint)"] = @{ Subject="$($_.Subject)"; Store=$store; Thumbprint="$($_.Thumbprint)"; Issuer="$($_.Issuer)"; Expires=("$($_.NotAfter)"); FriendlyName="$($_.FriendlyName)" } } } catch {}
    }
    $s.Certificates = $certs
    # DRIVERS (driver-store packages = a fast proxy for "drivers added").
    $drv = @{}
    try { Get-ChildItem -LiteralPath "$env:SystemRoot\System32\DriverStore\FileRepository" -Directory -ErrorAction SilentlyContinue | ForEach-Object { $drv[$_.Name] = @{ Name=$_.Name; Inf=(("$($_.Name)".Split('.')[0]) + '.inf'); Added=("$($_.LastWriteTime)") } } } catch {}
    $s.Drivers = $drv
    # PRINTERS + print drivers.
    $prn = @{}
    try { Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { $prn["P:$($_.Name)"] = @{ Name=$_.Name; Kind='printer' } } } catch {}
    try { Get-PrinterDriver -ErrorAction SilentlyContinue | ForEach-Object { $prn["D:$($_.Name)"] = @{ Name=$_.Name; Kind='driver' } } } catch {}
    $s.Printers = $prn
    # PROGRAM FOLDERS (top-level dirs - a new dir = the app's install folder; cheap vs a full file walk).
    $dirs = @{}
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) {
        try { Get-ChildItem -LiteralPath $pf -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $dirs["$pf\$($_.Name)"] = @{ Name=$_.Name; Root=$pf } } } catch {}
    }
    $s.ProgramDirs = $dirs
    # DEEP, whole-system maps (the complete picture). Stored under underscore keys (Dictionary, not [hashtable])
    # so Compare-MachineSnapshot skips them - the raw diff is done by Get-SnapshotRawDiff. EnvVars is a plain
    # hashtable but also handled separately (it needs value-change detection the friendly diff doesn't do).
    if (-not $NoDeep) {
        # SysTracer-style THOROUGH scan: EVERY fixed drive (size+mtime -> detect add/modify/delete) AND registry
        # keys WITH values (detect value changes). Whole-drive coverage minus the pruned OS-churn folders; the
        # before/after diff + noise filter keep only real changes. Costs ~1-3 min depending on disk size; worth it.
        $script:SnapshotIncomplete = $false   # set true by Get-PathMap/Get-RegMap if a scan hit its cap (-> unreliable)
        $s._FileMap = Get-PathMap -Roots $script:SnapshotFileRoots
        $s._RegMap  = Get-RegMap  -Roots $script:SnapshotRegRoots -ValuesToo
        $s._EnvVars = Get-EnvSnapshot
        $s._Incomplete = [bool]$script:SnapshotIncomplete   # surfaced in the dialog so a capped/unreliable scan is never silent
    }
    return $s
}

# Diff two snapshots -> per-category ADDED items, split into the app's changes vs filtered background noise.
# $AppVendor/$AppName seed the "always keep" tokens so the app's own vendor (even if it's on the noise list,
# e.g. Citrix/McAfee) is never hidden.
function Compare-MachineSnapshot {
    param([hashtable]$Before, [hashtable]$After, [string]$AppVendor, [string]$AppName)
    $appTokens = Get-AppMatchTokens -Vendor $AppVendor -AppName $AppName
    $report = [ordered]@{}
    foreach ($cat in $After.Keys) {
        if ("$cat".StartsWith('_')) { continue }            # skip deep maps + env (_FileMap/_RegMap/_EnvVars) - diffed separately
        if ($After[$cat] -isnot [hashtable]) { continue }
        $b = $Before[$cat]; if (-not $b) { $b = @{} }
        $added = @(); $noise = @()
        # A NEW Add/Remove-Programs entry is ALWAYS the install's own footprint (a suite installs several - the app +
        # its bundled runtimes like Sentinel HASP), and the validator wants to SEE every one. So Programs is NOT
        # vendor-noise-filtered (the 'sentinel' token meant for the SentinelOne EDR was wrongly hiding Sentinel HASP).
        # Auto-UNINSTALL still excludes shared MS runtimes (VC++/.NET) - see Get-UninstallFromSnapshotDiff.
        $skipNoise = ("$cat" -eq 'Programs')
        foreach ($id in $After[$cat].Keys) {
            if ($b.ContainsKey($id)) { continue }
            $item = $After[$cat][$id]
            $text = ($item.Values -join ' ') + ' ' + $id
            if ((-not $skipNoise) -and (Test-IsSnapshotNoise -Text $text -AppTokens $appTokens)) { $noise += [pscustomobject]@{ Id=$id; Info=$item } }
            else { $added += [pscustomobject]@{ Id=$id; Info=$item } }
        }
        $report[$cat] = [ordered]@{ Added = $added; Noise = $noise }
    }
    return $report
}

# Parse a stored registry value string (name<SOH>type<SOH>value<STX>...) -> ordered @{ name = @{ Type; Value } }.
function ConvertFrom-RegValueString {
    param([string]$S)
    $out = [ordered]@{}
    if (-not "$S") { return $out }
    foreach ($rec in ("$S" -split [char]2)) {
        if (-not $rec) { continue }
        $parts = $rec -split [char]1, 3
        if ($parts.Count -lt 3) { continue }
        $nm = if ("$($parts[0])") { $parts[0] } else { '(Default)' }
        $out[$nm] = @{ Type = "$($parts[1])"; Value = "$($parts[2])" }
    }
    return $out
}
# Per-value diff between BEFORE and AFTER value strings for one key. Returns @(@{ Name; Type; Value; Old; New; Change }).
# Change = 'added' (new key or new value), 'removed', 'changed' (value differs -> Old/New), or 'same' (kept, for context).
function Compare-RegValueStrings {
    param([string]$Before, [string]$After, [switch]$IncludeSame)
    $b = ConvertFrom-RegValueString $Before; $a = ConvertFrom-RegValueString $After
    $out = @()
    foreach ($nm in @($a.Keys)) {
        $av = $a[$nm]
        if (-not $b.Contains($nm)) { $out += @{ Name=$nm; Type=$av.Type; Value=$av.Value; Old=''; New=$av.Value; Change='added' } }
        elseif ("$($b[$nm].Value)" -ne "$($av.Value)") { $out += @{ Name=$nm; Type=$av.Type; Value=$av.Value; Old="$($b[$nm].Value)"; New=$av.Value; Change='changed' } }
        elseif ($IncludeSame) { $out += @{ Name=$nm; Type=$av.Type; Value=$av.Value; Old=$av.Value; New=$av.Value; Change='same' } }
    }
    foreach ($nm in @($b.Keys)) { if (-not $a.Contains($nm)) { $out += @{ Name=$nm; Type=$b[$nm].Type; Value=$b[$nm].Value; Old="$($b[$nm].Value)"; New=''; Change='removed' } } }
    return $out
}

# Diff the DEEP maps: every path/key that is NEW (absent in Before) or MODIFIED (signature changed) in After.
# $Kind = 'Files' or 'Registry'. OS churn is routed to a NOISE count (not dropped). Returns objects {Path; Change}
# plus counts. Deletions (present in Before, gone in After) are counted too, for completeness.
function Get-SnapshotRawDiff {
    param($Before, $After, [ValidateSet('Files','Registry')][string]$Kind, [string[]]$AppTokens)
    $bmap = if ($Kind -eq 'Files') { $Before._FileMap } else { $Before._RegMap }
    $amap = if ($Kind -eq 'Files') { $After._FileMap }  else { $After._RegMap }
    $new = New-Object System.Collections.Generic.List[object]
    $noiseItems = New-Object System.Collections.Generic.List[object]   # RETAINED (capped) so the user can view the ignored set + promote items into the new logics
    $noise = 0; $modified = 0; $deleted = 0; $bytes = [long]0
    if ($amap) {
        foreach ($kv in $amap.GetEnumerator()) {
            $change = if (-not ($bmap -and $bmap.ContainsKey($kv.Key))) { 'new' }
                      elseif ($bmap[$kv.Key] -ne $kv.Value) { 'modified' } else { $null }
            if (-not $change) { continue }
            $isApp  = Test-IsAppItem -Text $kv.Key -AppTokens $AppTokens
            $churn  = if ($Kind -eq 'Files') { Test-IsFileNoise $kv.Key } else { Test-IsRegNoise $kv.Key }
            # Noise rules:
            #  - a MODIFIED (not newly-created) FILE outside the app is background churn (installers ADD their files, they
            #    don't quietly modify unrelated ones) -> kills the giant "modified" junk (reparse farms, caches, profile
            #    churn, catroot2/wbem).
            #  - an ADDED file is REAL install footprint - the app AND its bundled prerequisites (VC++/.NET/etc.). We do
            #    NOT vendor-filter added files (that was hiding VC++), only OS-churn regex hides one. Vendor-noise still
            #    applies to MODIFIED files + all registry (which churn under vendor keys regardless of installs).
            if ($Kind -eq 'Files' -and $change -eq 'new') {
                # ADDED file: keep the app's own AND bundled prerequisites (VC++/.NET); only OS-churn or vendor auto-update
                # churn (browser/AV, NOT a prerequisite) hides one.
                $isNoise = (-not $isApp) -and (-not (Test-IsPrereqFile $kv.Key)) -and ($churn -or (Test-IsVendorNoise -Text $kv.Key -AppTokens $AppTokens))
            } elseif ($Kind -eq 'Registry' -and $change -eq 'new') {
                # ADDED registry KEY = a real structural change - keep it even under a vendor/Microsoft path (a replaced
                # component / a Chrome/Edge policy key etc. is a real change the packager must see). Only MRU/telemetry
                # churn (Test-IsRegNoise) hides one.
                $isNoise = (-not $isApp) -and $churn
            } else {
                # A MODIFIED Add/Remove-Programs (ARP) key = a component REPLACED in place (its DisplayVersion changed) -
                # keep it even under a Microsoft/vendor path; the tree shows the version old -> new. Everything else modified
                # under a vendor/OS path is background churn.
                $isArp = ($Kind -eq 'Registry') -and ("$($kv.Key)" -match '(?i)\\Uninstall\\')
                $isNoise = (-not $isApp) -and (-not $isArp) -and ($churn -or (Test-IsVendorNoise -Text $kv.Key -AppTokens $AppTokens) -or ($Kind -eq 'Files' -and $change -eq 'modified'))
            }
            if ($isNoise) { $noise++; if ($noiseItems.Count -lt 5000) { $noiseItems.Add([pscustomobject]@{ Path = $kv.Key; Change = $change; IsApp = $false }) }; continue }
            if ($change -eq 'modified') { $modified++ }
            # Sum the installed FILE bytes (value = 'size|mtimeTicks') - the real footprint, for an accurate FreeSpace.
            if ($Kind -eq 'Files') { $sz = 0; [long]::TryParse(("$($kv.Value)".Split('|')[0]), [ref]$sz) | Out-Null; $bytes += $sz }
            # Registry: carry the per-VALUE diff (added/removed/changed with old->new) so the report shows exactly what
            # changed inside the key - captured from the snapshot, so it survives save/load + is correct after uninstall.
            $vals = $null
            if ($Kind -eq 'Registry') { $bv = if ($bmap -and $bmap.ContainsKey($kv.Key)) { "$($bmap[$kv.Key])" } else { '' }; $vals = @(Compare-RegValueStrings -Before $bv -After "$($kv.Value)") }
            $new.Add([pscustomobject]@{ Path = $kv.Key; Change = $change; IsApp = $isApp; Values = $vals })
        }
    }
    $del = New-Object System.Collections.Generic.List[object]
    if ($bmap) { foreach ($k in $bmap.Keys) { if (-not ($amap -and $amap.ContainsKey($k))) {
        $isApp = Test-IsAppItem -Text $k -AppTokens $AppTokens
        $churn = if ($Kind -eq 'Files') { Test-IsFileNoise $k } else { Test-IsRegNoise $k }
        # A REMOVED file/key is a real change (a replaced component removes its OLD version) - show it even under a vendor
        # path; only OS/MRU churn hides a removal. (Removals in the short capture window are almost always the install.)
        if ((-not $isApp) -and $churn) { $deleted++ }
        else { $del.Add([pscustomobject]@{ Path=$k; Change='deleted'; IsApp=$isApp }) }
    } } }
    # Return .ToArray() (object[]) NOT the List[object] - @() / comma on a List[object] of PSObjects throws
    # "Argument types do not match" in PS 5.1 (see memory ps51-list-object-wrap), which broke the analyze report.
    return [pscustomobject]@{ New = $new.ToArray(); Deleted = $del.ToArray(); NoiseItems = $noiseItems.ToArray(); NoiseCount = $noise; ModifiedCount = $modified; DeletedCount = $deleted; InstalledBytes = $bytes; Total = $(if ($amap) { $amap.Count } else { 0 }) }
}

# Extract the app's PER-USER (HKCU) registry VALUES the install wrote, so a Per-user config (all-users-reg /
# Active Setup) can be auto-populated with the REAL detected settings instead of a placeholder. Reads the live values
# (the snapshot just ran on this machine, so HKCU is current) and returns @(@{ Key; Name; Value; Type }). Only the
# app's OWN HKCU keys (IsApp) are taken. NOTE: per-user settings written only at FIRST LAUNCH won't be here - this is
# the install-time footprint, the right starting point that the packager reviews.
function Get-SnapshotHkcuValues {
    param($RegDiff, [string[]]$AppTokens)
    $out  = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    # Every NEW/MODIFIED HKCU key in the diff is the install's per-user footprint - the diff already dropped OS churn
    # and known 3rd-party vendors (Test-IsRegNoise/Test-IsVendorNoise), so we DON'T also require a name match here:
    # an app that writes HKCU under a codename key would otherwise be silently missed. Reliability > minimalism.
    foreach ($it in @($RegDiff.New)) {
        $p = "$($it.Path)"
        if ($p -notmatch '^(?i)HK(CU|EY_CURRENT_USER)\\') { continue }   # per-user hive only
        $prov = ($p -replace '^(?i)HKEY_CURRENT_USER\\', 'HKCU:\' -replace '^(?i)HKCU\\', 'HKCU:\')
        $lc = $prov.ToLower(); if ($seen.ContainsKey($lc)) { continue }; $seen[$lc] = $true
        try {
            $k = Get-Item -LiteralPath $prov -ErrorAction Stop
            foreach ($vn in $k.GetValueNames()) {
                if (-not "$vn") { continue }   # skip the (Default) value - rarely a real per-user setting
                $out.Add([pscustomobject]@{ Key = $prov; Name = $vn; Value = $k.GetValue($vn); Type = "$($k.GetValueKind($vn))" })
            }
        } catch {}
    }
    return $out.ToArray()
}

# Extract the per-user FILES the install wrote under the packager's profile (AppData Roaming/Local/LocalLow), so a
# Per-user config can stage them in SupportFiles and copy them into EVERY user profile (Get-ADTUserProfiles loop).
# The file diff already dropped OS churn + temp/cache + known vendors, so what's left under AppData is the install's
# real per-user file footprint. Returns @(@{ Source; Scope; Rel }) - Scope = Roaming|Local|LocalLow, Rel = the path
# under that scope (subdirs + filename). Bounded: skips huge files and caps the count so a cache blowup can't bloat.
function Get-SnapshotUserFiles {
    param($FileDiff, [string[]]$AppTokens, [int]$MaxFiles = 200, [long]$MaxBytesEach = 200MB)
    $local = "$env:LOCALAPPDATA"
    $scopes = @()
    if ("$env:APPDATA") { $scopes += [pscustomobject]@{ Root = "$env:APPDATA".TrimEnd('\'); Scope = 'Roaming' } }
    if ($local) { $scopes += [pscustomobject]@{ Root = (Join-Path (Split-Path $local -Parent) 'LocalLow').TrimEnd('\'); Scope = 'LocalLow' } }
    if ($local) { $scopes += [pscustomobject]@{ Root = $local.TrimEnd('\'); Scope = 'Local' } }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($it in @($FileDiff.New)) {
        if ($out.Count -ge $MaxFiles) { break }
        $f = "$($it.Path)"; $low = $f.ToLower(); $hit = $null
        foreach ($sc in $scopes) { if ($low.StartsWith($sc.Root.ToLower() + '\')) { $hit = $sc; break } }   # LocalLow before Local
        if (-not $hit) { continue }
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        try { if ((Get-Item -LiteralPath $f -ErrorAction Stop).Length -gt $MaxBytesEach) { continue } } catch { continue }
        $out.Add([pscustomobject]@{ Source = $f; Scope = $hit.Scope; Rel = $f.Substring($hit.Root.Length).TrimStart('\') })
    }
    return $out.ToArray()
}

# Diff environment variables (machine + user): added or value-changed. Returns @(@{ Name; Old; New; Change }).
function Get-EnvDiff {
    param($Before, $After)
    $b = $Before._EnvVars; $a = $After._EnvVars
    $out = New-Object System.Collections.Generic.List[object]
    if ($a) { foreach ($kv in $a.GetEnumerator()) {
        if (-not ($b -and $b.ContainsKey($kv.Key))) { $out.Add([pscustomobject]@{ Name=$kv.Key; Old=''; New=$kv.Value; Change='added' }) }
        elseif ("$($b[$kv.Key])" -ne "$($kv.Value)") { $out.Add([pscustomobject]@{ Name=$kv.Key; Old="$($b[$kv.Key])"; New=$kv.Value; Change='changed' }) }
    } }
    return $out.ToArray()
}

# ---------- Change-TREE builders (SysTracer-style view). Pure logic; the WPF rendering lives in GUI.ps1. ----------
# Build a nested tree (hashtable name -> @{ n; f; s; c }) from { Path; Change } items. $Sep splits the hierarchy
# (\ for files/registry). Leaf node carries .s = 'new'|'modified'|'deleted'; intermediates aggregate via the counts fn.
function Add-SnapshotTreePath {
    param($Root, [string]$Path, [string]$Status, [string]$Sep = '\')
    $segs = @("$Path".Split($Sep) | Where-Object { $_ -ne '' })
    if (-not $segs.Count) { return }
    $cur = $Root; $acc = ''
    for ($i = 0; $i -lt $segs.Count; $i++) {
        $seg = $segs[$i]; $acc = if ($acc) { "$acc$Sep$seg" } else { $seg }
        if (-not $cur.Contains($seg)) { $cur[$seg] = @{ n = $seg; f = $acc; s = $null; c = [ordered]@{} } }
        if ($i -eq $segs.Count - 1) { $cur[$seg].s = $Status }
        $cur = $cur[$seg].c
    }
}
# Aggregate add/mod/del counts under a node (incl. itself). Returns @{ new; modified; deleted }.
function Get-SnapshotTreeCounts {
    param($Node, [hashtable]$Cache)
    # $Cache MEMOISES the aggregate per node (keyed by its full path). The tree UI asks for a count on EVERY node it
    # renders; without a cache each of those re-walks that node's whole subtree, making the build O(n^2) - which is what
    # hung the window on a huge install (a 10 GB app -> tens of thousands of changed files). Callers that pass no cache
    # behave exactly as before. A node with no .f (synthetic root, e.g. in tests) is simply not cached.
    $k = "$($Node.f)"
    if ($Cache -and $k -and $Cache.ContainsKey($k)) { return $Cache[$k] }
    $r = @{ new = 0; modified = 0; deleted = 0 }
    if ($Node.s -and $r.ContainsKey($Node.s)) { $r[$Node.s]++ }
    foreach ($ch in $Node.c.Values) { $cc = Get-SnapshotTreeCounts -Node $ch -Cache $Cache; $r.new += $cc.new; $r.modified += $cc.modified; $r.deleted += $cc.deleted }
    if ($Cache -and $k) { $Cache[$k] = $r }
    return $r
}

# Live registry values under a diff-form key path (HKLM\...), as @(@{ Name; Type; Value }). Captured at changeset-build
# time so the report/export is SELF-CONTAINED (import doesn't need the live machine, whose state may have changed).
function Get-SnapshotRegValuesFor {
    param([string]$KeyPath, [int]$Max = 60)
    $out = @()
    $prov = ($KeyPath -replace '^(?i)HKEY_LOCAL_MACHINE\\','HKLM:\' -replace '^(?i)HKLM\\','HKLM:\' -replace '^(?i)HKEY_CURRENT_USER\\','HKCU:\' -replace '^(?i)HKCU\\','HKCU:\' -replace '^(?i)HKEY_CLASSES_ROOT\\','HKCR:\' -replace '^(?i)HKEY_USERS\\','HKU:\')
    try {
        $k = Get-Item -LiteralPath $prov -ErrorAction Stop
        foreach ($vn in $k.GetValueNames()) {
            if ($out.Count -ge $Max) { break }
            $nm = if ("$vn") { "$vn" } else { '(Default)' }; $val = "$($k.GetValue($vn))"
            if ($val.Length -gt 400) { $val = $val.Substring(0,400) + '…' }
            $out += @{ Name = $nm; Type = "$($k.GetValueKind($vn))"; Value = $val }
        }
    } catch {}
    return $out
}

# Normalise the analyze diff into ONE self-contained "change set" hashtable: files (with live size/date), registry
# (with captured values), the list categories, env, and a capped noise sample + counts. This is what the tree renders,
# what Copy/Export write, and what Import reads back - fully JSON-serializable.
function New-SnapshotChangeSet {
    param($Diff, $FileDiff, $RegDiff, $EnvChanges, [string]$AppName = '', [int]$MaxNoise = 400, [int]$MaxRegValues = 3000)
    $cs = [ordered]@{ App = "$AppName"; When = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Counts = @{ new=0; modified=0; deleted=0 }
                      Files = @(); Registry = @(); RegValues = @{}; Lists = [ordered]@{}; Env = @(); Noise = @() }
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($it in @($FileDiff.New)) {
        $ch = if ("$($it.Change)" -eq 'modified') { 'modified' } else { 'new' }
        $sz = $null; $md = $null
        try { if (Test-Path -LiteralPath "$($it.Path)" -PathType Leaf) { $fi = Get-Item -LiteralPath "$($it.Path)" -ErrorAction Stop; $sz = [long]$fi.Length; $md = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } } catch {}
        $files.Add(@{ Path = "$($it.Path)"; Change = $ch; Size = $sz; Modified = $md })
        if ($ch -eq 'modified') { $cs.Counts.modified++ } else { $cs.Counts.new++ }
    }
    foreach ($it in @($FileDiff.Deleted)) { $files.Add(@{ Path = "$($it.Path)"; Change = 'deleted'; Size = $null; Modified = $null }); $cs.Counts.deleted++ }
    $cs.Files = $files.ToArray()
    $regs = New-Object System.Collections.Generic.List[object]; $vc = 0
    foreach ($it in @($RegDiff.New)) {
        $ch = if ("$($it.Change)" -eq 'modified') { 'modified' } else { 'new' }
        $regs.Add(@{ Path = "$($it.Path)"; Change = $ch })
        if ($ch -eq 'modified') { $cs.Counts.modified++ } else { $cs.Counts.new++ }
        if ($vc -lt $MaxRegValues) {
            # Prefer the diff-carried per-value changes (added/removed/changed w/ old->new). Fall back to a live read
            # (older snapshots without captured values). Store as @{ Name; Type; Value; Old; New; Change }.
            $vals = @($it.Values)
            if (-not $vals.Count) { $vals = @(Get-SnapshotRegValuesFor -KeyPath "$($it.Path)" | ForEach-Object { @{ Name=$_.Name; Type=$_.Type; Value=$_.Value; Old=''; New=$_.Value; Change='added' } }) }
            if ($vals.Count) { $cs.RegValues["$($it.Path)"] = $vals; $vc += $vals.Count }
        }
    }
    foreach ($it in @($RegDiff.Deleted)) { $regs.Add(@{ Path = "$($it.Path)"; Change = 'deleted' }); $cs.Counts.deleted++ }
    $cs.Registry = $regs.ToArray()
    if ($Diff) {
        $catTitles = [ordered]@{ Shortcuts='Shortcuts'; Services='Services'; Tasks='Scheduled tasks'; RunKeys='Autostart (Run keys)'; Drivers='Drivers'; Certificates='Certificates'; Printers='Printers'; Programs='Programs (Add / Remove)' }
        foreach ($ck in $catTitles.Keys) {
            if (-not $Diff[$ck]) { continue }
            $add = @($Diff[$ck].Added); if (-not $add.Count) { continue }
            $items = @()
            foreach ($item in $add) {
                $info = $item.Info; if (-not $info) { $info = @{} }
                $label = "$($info.DisplayName)"
                foreach ($lk in 'Name','FriendlyName','Subject') { if (-not "$label".Trim()) { $label = "$($info[$lk])" } }   # certs have no DisplayName/Name -> use FriendlyName/Subject
                if (-not "$label".Trim()) { $label = "$($item.Id)" }
                $fields = [ordered]@{}; foreach ($k in @($info.Keys | Sort-Object)) { $v = "$($info[$k])"; if ($v.Trim()) { $fields["$k"] = $v } }
                $items += @{ Label = $label; Fields = $fields }; $cs.Counts.new++
            }
            $cs.Lists["$($catTitles[$ck])"] = $items
        }
    }
    foreach ($e in @($EnvChanges)) { $cs.Env += @{ Name = "$($e.Name)"; Old = "$($e.Old)"; New = "$($e.New)"; Change = "$($e.Change)" }; $cs.Counts.new++ }
    $nn = @(); foreach ($src in @($FileDiff, $RegDiff)) { foreach ($ni in (@($src.NoiseItems) | Select-Object -First $MaxNoise)) { $nn += "$($ni.Path)" } }
    $cs.Noise = $nn
    return $cs
}

# Reconstruct a STRUCTURAL change set from a report saved by an OLDER build that didn't persist a ChangeSet, so the
# Tree view still works on it. Source: LeftoverCandidates (everything the install created - files/folders/reg keys, as
# removal commands we parse the path out of) + Shortcuts. Added items only (no per-value detail / no 'modified') - it is
# an honest reconstruction of "what was created", enough to render a clear tree.
function New-SnapshotChangeSetFromState {
    param([Parameter(Mandatory)]$State, [string]$AppName = '')
    $cs = [ordered]@{ App = "$AppName"; When = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Counts = @{ new=0; modified=0; deleted=0 }
                      Files = @(); Registry = @(); RegValues = @{}; Lists = [ordered]@{}; Env = @(); Noise = @() }
    $files = New-Object System.Collections.Generic.List[object]
    $regs  = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($State.LeftoverCandidates)) {
        $cmd = "$($c.Command)"
        if ($cmd -match '(?i)Remove-ADTRegistryKey') {
            if ($cmd -match "-Key\s+'([^']+)'" -or $cmd -match '-Key\s+"([^"]+)"' -or $cmd -match '-Key\s+(\S+)') {
                $k = "$($Matches[1])".Trim("'`" "); if ($k) { $regs.Add(@{ Path = $k; Change = 'new' }); $cs.Counts.new++ }
            }
        } elseif ($cmd -match '(?i)Remove-ADT(Folder|File)') {
            if ($cmd -match "-Path\s+'([^']+)'" -or $cmd -match '-Path\s+"([^"]+)"' -or $cmd -match '-Path\s+(\S+)') {
                $p = "$($Matches[1])".Trim("'`" ")
                if ($p) {
                    $sz=$null; $md=$null
                    try { if (Test-Path -LiteralPath $p -PathType Leaf) { $fi=Get-Item -LiteralPath $p -EA Stop; $sz=[long]$fi.Length; $md=$fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } } catch {}
                    $files.Add(@{ Path=$p; Change='new'; Size=$sz; Modified=$md }); $cs.Counts.new++
                }
            }
        }
    }
    $cs.Files = $files.ToArray(); $cs.Registry = $regs.ToArray()
    $sc = @()
    foreach ($s in @($State.Shortcuts)) {
        $nm = if ("$($s.Name)".Trim()) { "$($s.Name)" } elseif ("$($s.Lnk)".Trim()) { [IO.Path]::GetFileNameWithoutExtension("$($s.Lnk)") } else { '' }
        if (-not "$nm".Trim()) { continue }
        $f = [ordered]@{}; if ("$($s.Target)".Trim()) { $f['Target']="$($s.Target)" }; if ("$($s.Lnk)".Trim()) { $f['Shortcut']="$($s.Lnk)" }
        $sc += @{ Label = $nm; Fields = $f }; $cs.Counts.new++
    }
    if ($sc.Count) { $cs.Lists['Shortcuts'] = $sc }
    return $cs
}

# Human size (KB/MB/GB) for a byte count.
function Format-PBSize { param($Bytes) if ($null -eq $Bytes) { return '' }; $b=[double]$Bytes; if ($b -ge 1GB){ '{0:N1} GB' -f ($b/1GB) } elseif ($b -ge 1MB){ '{0:N1} MB' -f ($b/1MB) } elseif ($b -ge 1KB){ '{0:N0} KB' -f ($b/1KB) } else { "$([int]$b) B" } }

# Plain indented TEXT of a change set (for Copy + .txt export). Marks [+] added / [~] modified / [-] removed.
function Format-SnapshotChangeSetText {
    param($ChangeSet)
    $cs = $ChangeSet; $mk = @{ new='[+]'; modified='[~]'; deleted='[-]' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("$($cs.App) - snapshot changes ($($cs.When))")
    [void]$sb.AppendLine("$($cs.Counts.new) added, $($cs.Counts.modified) modified, $($cs.Counts.deleted) removed")
    if (@($cs.Files).Count) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine("FILES & FOLDERS ($(@($cs.Files).Count))")
        foreach ($f in (@($cs.Files) | Sort-Object { "$($_.Path)" })) {
            $extra = @(); if ($f.Size) { $extra += (Format-PBSize $f.Size) }; if ($f.Modified) { $extra += "$($f.Modified)" }
            [void]$sb.AppendLine("  $($mk["$($f.Change)"]) $($f.Path)$(if($extra.Count){"   ($($extra -join ', '))"})")
        }
    }
    if (@($cs.Registry).Count) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine("REGISTRY ($(@($cs.Registry).Count))")
        $vmk = @{ added='[+]'; removed='[-]'; changed='[~]'; same='   ' }
        foreach ($r in (@($cs.Registry) | Sort-Object { "$($_.Path)" })) {
            [void]$sb.AppendLine("  $($mk["$($r.Change)"]) $($r.Path)")
            foreach ($v in @($cs.RegValues["$($r.Path)"])) {
                $body = if ("$($v.Change)" -eq 'changed') { "$($v.Name) [$($v.Type)] : $($v.Old)  ->  $($v.New)" }
                        elseif ("$($v.Change)" -eq 'removed') { "$($v.Name) [$($v.Type)]  (removed)" }
                        else { "$($v.Name) [$($v.Type)] = $($v.New)" }
                [void]$sb.AppendLine("        $($vmk["$($v.Change)"]) $body")
            }
        }
    }
    foreach ($catName in @($cs.Lists.Keys)) {
        $items = @($cs.Lists[$catName]); if (-not $items.Count) { continue }
        [void]$sb.AppendLine(''); [void]$sb.AppendLine("$($catName.ToUpper()) ($($items.Count))")
        foreach ($it in $items) { [void]$sb.AppendLine("  [+] $($it.Label)"); foreach ($fk in @($it.Fields.Keys)) { [void]$sb.AppendLine("        $fk = $($it.Fields[$fk])") } }
    }
    if (@($cs.Env).Count) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine("ENVIRONMENT ($(@($cs.Env).Count))")
        foreach ($e in @($cs.Env)) { [void]$sb.AppendLine("  [$(if("$($e.Change)" -eq 'added'){'+'}else{'~'})] $($e.Name) = $(if($e.Old){"$($e.Old) -> "})$($e.New)") }
    }
    if (@($cs.Noise).Count) { [void]$sb.AppendLine(''); [void]$sb.AppendLine("IGNORED - OS / third-party noise ($(@($cs.Noise).Count) shown; not part of the package)") }
    return $sb.ToString()
}

# Colour-coded self-contained HTML of a change set (for Export - opens in any browser, shareable).
function Format-SnapshotChangeSetHtml {
    param($ChangeSet)
    $cs = $ChangeSet
    $col = @{ new='#3fa34d'; modified='#c99a1e'; deleted='#cf3b3b' }; $mk = @{ new='added'; modified='modified'; deleted='removed' }
    $enc = { param($s) "$s" -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<!doctype html><html><head><meta charset='utf-8'><title>$(& $enc $cs.App) - snapshot changes</title><style>body{font-family:Segoe UI,Arial,sans-serif;background:#1b1d22;color:#d7d7d7;margin:24px} h1{font-size:18px;font-weight:500} h2{font-size:14px;border-bottom:1px solid #333;padding-bottom:4px;margin-top:26px} .row{font-family:Consolas,monospace;font-size:12.5px;padding:3px 8px;border-left:3px solid #555;margin:2px 0;background:#22252c} .v{font-family:Consolas,monospace;font-size:11.5px;color:#9aa4b2;margin-left:28px;padding:1px 0} .b{font-size:10.5px;padding:1px 6px;border-radius:3px;margin-right:6px} .cnt{color:#8a929e;font-size:12px}</style></head><body>")
    [void]$sb.Append("<h1>$(& $enc $cs.App) &mdash; snapshot changes <span class='cnt'>($(& $enc $cs.When))</span></h1>")
    [void]$sb.Append("<p><span class='b' style='background:#12331a;color:#3fa34d'>$($cs.Counts.new) added</span><span class='b' style='background:#332a12;color:#c99a1e'>$($cs.Counts.modified) modified</span><span class='b' style='background:#331414;color:#cf3b3b'>$($cs.Counts.deleted) removed</span></p>")
    $rowFn = { param($ch,$text,$extra) $c=$col[$ch]; "<div class='row' style='border-left-color:$c'><span class='b' style='background:${c}33;color:$c'>$($mk[$ch])</span>$(& $enc $text)$(if($extra){" <span class='cnt'>$(& $enc $extra)</span>"})</div>" }
    if (@($cs.Files).Count) {
        [void]$sb.Append("<h2>Files &amp; folders ($(@($cs.Files).Count))</h2>")
        foreach ($f in (@($cs.Files) | Sort-Object { "$($_.Path)" })) { $ex=@(); if($f.Size){$ex+=(Format-PBSize $f.Size)}; if($f.Modified){$ex+="$($f.Modified)"}; [void]$sb.Append((& $rowFn "$($f.Change)" "$($f.Path)" ($ex -join ', '))) }
    }
    if (@($cs.Registry).Count) {
        [void]$sb.Append("<h2>Registry ($(@($cs.Registry).Count))</h2>")
        foreach ($r in (@($cs.Registry) | Sort-Object { "$($_.Path)" })) {
            [void]$sb.Append((& $rowFn "$($r.Change)" "$($r.Path)" ''))
            foreach ($v in @($cs.RegValues["$($r.Path)"])) {
                $vc2 = switch ("$($v.Change)") { 'added' {$col.new} 'removed' {$col.deleted} 'changed' {$col.modified} default {'#9aa4b2'} }
                $body = if ("$($v.Change)" -eq 'changed') { "$(& $enc $v.Name) [$(& $enc $v.Type)] : <span style='color:$($col.deleted)'>$(& $enc $v.Old)</span> &rarr; <span style='color:$($col.new)'>$(& $enc $v.New)</span>" }
                        elseif ("$($v.Change)" -eq 'removed') { "$(& $enc $v.Name) [$(& $enc $v.Type)] (removed)" }
                        else { "$(& $enc $v.Name) [$(& $enc $v.Type)] = $(& $enc $v.New)" }
                [void]$sb.Append("<div class='v' style='color:$vc2'>$body</div>")
            }
        }
    }
    foreach ($catName in @($cs.Lists.Keys)) {
        $items=@($cs.Lists[$catName]); if(-not $items.Count){continue}
        [void]$sb.Append("<h2>$(& $enc $catName) ($($items.Count))</h2>")
        foreach ($it in $items) { [void]$sb.Append((& $rowFn 'new' "$($it.Label)" '')); foreach ($fk in @($it.Fields.Keys)) { [void]$sb.Append("<div class='v'>$(& $enc $fk) = $(& $enc $it.Fields[$fk])</div>") } }
    }
    if (@($cs.Env).Count) { [void]$sb.Append("<h2>Environment ($(@($cs.Env).Count))</h2>"); foreach ($e in @($cs.Env)) { [void]$sb.Append((& $rowFn $(if("$($e.Change)" -eq 'added'){'new'}else{'modified'}) "$($e.Name) = $(if($e.Old){"$($e.Old) -> "})$($e.New)" '')) } }
    if (@($cs.Noise).Count) { [void]$sb.Append("<h2 style='color:#8a929e'>Ignored &mdash; OS / third-party noise ($(@($cs.Noise).Count))</h2>") }
    [void]$sb.Append("</body></html>")
    return $sb.ToString()
}

# Export the REGISTRY changes of a change set as a standard Windows .reg file (import into regedit / inspect). Added &
# changed keys get their values; deleted keys become [-HKEY_...]; removed values become "name"=-. String + DWord are
# encoded properly; other types are best-effort as strings (fine for inspection - flag on the line).
function Format-SnapshotChangeSetReg {
    param($ChangeSet)
    $cs = $ChangeSet
    $esc = { param($s) ("$s" -replace '\\','\\' -replace '"','\"') }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Windows Registry Editor Version 5.00'); [void]$sb.AppendLine('')
    if ($cs.App) { [void]$sb.AppendLine("; Registry changes from: $($cs.App)  ($($cs.When))"); [void]$sb.AppendLine('') }
    foreach ($r in (@($cs.Registry) | Sort-Object { "$($_.Path)" })) {
        $keyFull = ("$($r.Path)" -replace '^(?i)HKLM\\','HKEY_LOCAL_MACHINE\' -replace '^(?i)HKCU\\','HKEY_CURRENT_USER\' -replace '^(?i)HKCR\\','HKEY_CLASSES_ROOT\' -replace '^(?i)HKU\\','HKEY_USERS\')
        if ("$($r.Change)" -eq 'deleted') { [void]$sb.AppendLine("[-$keyFull]"); [void]$sb.AppendLine(''); continue }
        [void]$sb.AppendLine("[$keyFull]")
        foreach ($v in @($cs.RegValues["$($r.Path)"])) {
            $nm = if ("$($v.Name)" -eq '(Default)') { '@' } else { '"' + (& $esc $v.Name) + '"' }
            if ("$($v.Change)" -eq 'removed') { [void]$sb.AppendLine("$nm=-"); continue }
            $val = if ("$($v.New)") { "$($v.New)" } else { "$($v.Value)" }
            $enc = switch ("$($v.Type)") {
                'DWord' { $n=0; [void][int]::TryParse(("$val" -replace '[^0-9\-]',''), [ref]$n); 'dword:' + ('{0:x8}' -f ([uint32]($n -band 0xFFFFFFFF))) }
                default { '"' + (& $esc $val) + '"' }
            }
            $note = if ("$($v.Type)" -notin 'DWord','String','ExpandString') { "  ; [$($v.Type)] best-effort" } else { '' }
            [void]$sb.AppendLine("$nm=$enc$note")
        }
        [void]$sb.AppendLine('')
    }
    return $sb.ToString()
}

# Recursively turn a ConvertFrom-Json PSCustomObject graph into hashtables/arrays (PS 5.1 has no -AsHashtable), so an
# imported change set is shaped exactly like a freshly-built one for the tree renderer + formatters.
function ConvertTo-PBHashtable {
    param($Obj)
    if ($Obj -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}; foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-PBHashtable $p.Value }; return $h
    }
    if ($Obj -is [System.Collections.IEnumerable] -and $Obj -isnot [string]) { return @($Obj | ForEach-Object { ConvertTo-PBHashtable $_ }) }
    return $Obj
}

# Group a flat list of new paths/keys by a common parent prefix (first $Depth segments after the root), so the
# report shows "C:\Program Files\App\... - 847 items" instead of 847 lines. Returns @(@{ Prefix; Count; Sample }).
function Group-SnapshotPaths {
    param([string[]]$Paths, [int]$Depth = 4)
    $g = @{}
    foreach ($p in @($Paths)) {
        $segs = "$p".Split('\')
        $prefix = if ($segs.Count -le $Depth) { "$p" } else { ($segs[0..($Depth-1)] -join '\') + '\...' }
        if (-not $g.ContainsKey($prefix)) { $g[$prefix] = [pscustomobject]@{ Prefix=$prefix; Count=0; Sample=$p } }
        $g[$prefix].Count++
    }
    return @($g.Values | Sort-Object Count -Descending)
}

# Build the human-readable, COPYABLE snapshot report - SysTracer-style: organized by category, FULL PATHS (no
# "..." grouping), each item marked [+] added / [~] modified / [-] deleted, app's own changes first, background/
# OS/vendor junk HIDDEN (only a count). Returns one plain-text string (shown in the report box + Copy button).
function Get-SnapshotReportText {
    param($Diff, $FileDiff, $RegDiff, $EnvChanges, $Un, [string[]]$AppTokens, [int]$Cap = 5000,
          [string]$Search = '', [string]$OnlyCat = '', [switch]$IncludeNoise, [switch]$NoiseOnly)   # live filter: $Search = substring; $OnlyCat = one category key; -IncludeNoise appends the filtered-out items; -NoiseOnly emits ONLY them
    $L = New-Object System.Collections.Generic.List[string]
    $sx = "$Search".Trim()
    function _hit($text) { (-not $sx) -or ("$text".IndexOf($sx, [StringComparison]::OrdinalIgnoreCase) -ge 0) }
    function _showCat($k) { (-not "$OnlyCat".Trim()) -or ($OnlyCat -eq $k) }
    # Category order shown in the report (small categories list ALL their items - noise was already filtered out).
    $catLabel = [ordered]@{ Services='SERVICES'; Drivers='DRIVERS'; Certificates='CERTIFICATES'; Shortcuts='SHORTCUTS'; Tasks='SCHEDULED TASKS'; RunKeys='AUTOSTART (RUN KEYS)'; Printers='PRINTERS'; Programs='PROGRAMS (Add / Remove)' }
    function _mark($c) { switch ("$c") { 'modified' { 'MODIFIED' } 'deleted' { 'DELETED ' } default { 'ADDED   ' } } }
    function _rank($c) { switch ("$c") { 'modified' { 1 } 'deleted' { 2 } default { 0 } } }   # group added, then modified, then deleted
    function _itemLine($cat, $a) {
        switch ($cat) {
            'Programs'     { "$($a.Info.DisplayName) $($a.Info.DisplayVersion)$(if("$($a.Info.Publisher)".Trim()){"  ($($a.Info.Publisher))"})" }
            'Services'     { "$($a.Info.DisplayName)  [$($a.Id)]$(if("$($a.Info.Start)".Trim()){"  ($($a.Info.Start))"})  ->  $($a.Info.Path)" }
            'Tasks'        { "$($a.Info.Path)$($a.Info.Name)$(if("$($a.Info.Action)".Trim()){"   runs: $($a.Info.Action)"})$(if("$($a.Info.Triggers)".Trim()){"   [$($a.Info.Triggers)]"})" }
            'RunKeys'      { "$($a.Info.Name) = $($a.Info.Command)" }
            'Shortcuts'    { "$($a.Info.Name)$(if("$($a.Info.Target)".Trim()){"   ->  $($a.Info.Target)$(if("$($a.Info.Arguments)".Trim()){" $($a.Info.Arguments)"})"})   ($($a.Id))" }
            'Certificates' { "$($a.Info.Subject)   ($($a.Info.Store))   thumbprint $($a.Id.Split('\')[-1])$(if("$($a.Info.Expires)".Trim()){"   expires $($a.Info.Expires)"})" }
            'Drivers'      { "$($a.Info.Name)$(if("$($a.Info.Inf)".Trim()){"   (INF: $($a.Info.Inf))"})" }
            'Printers'     { "$($a.Info.Name)  ($($a.Info.Kind))" }
            default        { "$($a.Id)" }
        }
    }
    # Emit FULL paths (sorted), each marked +/~/-, capped so a giant set can't make a 100k-line report.
    function _emitPaths($items) {
        $arr = @($items | Sort-Object @{Expression={ _rank $_.Change }}, @{Expression={"$($_.Path)"}})   # added, then modified, then deleted
        $n = 0
        foreach ($it in $arr) {
            if ($n -ge $Cap) { $L.Add("      ... +$($arr.Count - $Cap) more (use 'Open full report (CMTrace)' for the full list)"); break }
            $L.Add("      $(_mark $it.Change)   $($it.Path)"); $n++
        }
    }
    # Registry emit: the key line PLUS the value(s) that CHANGED inside it (name = data [type]) - so the user sees
    # EXACTLY what was written without opening regedit. Values come from the snapshot diff (survive save/load + uninstall).
    function _emitReg($items) {
        $arr = @($items | Sort-Object @{Expression={ _rank $_.Change }}, @{Expression={"$($_.Path)"}})
        $n = 0
        foreach ($it in $arr) {
            if ($n -ge $Cap) { $L.Add("      ... +$($arr.Count - $Cap) more (use 'Open full report (CMTrace)' for the full list)"); break }
            $L.Add("      $(_mark $it.Change)   $($it.Path)"); $n++
            foreach ($v in @($it.Values)) {
                $nm = if ("$($v.Name)" -in @('','(Default)')) { '(Default)' } else { "$($v.Name)" }
                if ("$($v.Change)" -eq 'removed') { $L.Add("                  - removed value: $nm"); continue }
                $data = if ("$($v.New)".Length) { "$($v.New)" } else { "$($v.Value)" }
                if ("$data".Length -gt 200) { $data = "$($data.Substring(0,200))..." }
                $ty = if ("$($v.Type)".Trim()) { "  [$($v.Type)]" } else { '' }
                $vb = if ("$($v.Change)" -eq 'changed') { 'changed' } else { 'value  ' }
                $L.Add("                  $vb  $nm = $data$ty")
            }
        }
    }
    # FILES view for the validator: DON'T list every file - group by the FOLDER that received them and show
    # "<folder>\  (N file(s)) [tag]". A folder with few files (<=3) is expanded so small drops are still visible.
    # This is what a human validator wants ("these folders/files were created"), not 800 individual lines.
    function _emitFolders($items) {
        $byDir = @{}
        foreach ($it in @($items)) {
            $p = "$($it.Path)"; $dir = Split-Path $p -Parent; if (-not "$dir".Trim()) { $dir = $p }
            if (-not $byDir.ContainsKey($dir)) { $byDir[$dir] = New-Object System.Collections.Generic.List[object] }
            $byDir[$dir].Add($it)
        }
        $dirs = @($byDir.Keys | Sort-Object)
        $n = 0
        foreach ($d in $dirs) {
            if ($n -ge $Cap) { $L.Add("      ... +$($dirs.Count - $n) more folder(s)"); break }
            $files = $byDir[$d]
            $changes = @($files | ForEach-Object { "$($_.Change)" } | Select-Object -Unique)
            $tag = if ($changes.Count -eq 1) { _mark $changes[0] } else { 'CHANGED ' }
            $L.Add("      $tag   $d\   ($($files.Count) file$(if($files.Count -ne 1){'s'}))")
            if ($files.Count -le 3) {
                foreach ($f in @($files | Sort-Object { "$($_.Path)" })) { $L.Add("              - $(Split-Path "$($f.Path)" -Leaf)  [$(_mark $f.Change)]") }
            }
            $n++
        }
    }
    $appFiles = @(@($FileDiff.New) + @($FileDiff.Deleted) | Where-Object { $_.IsApp })
    $othFiles = @($FileDiff.New | Where-Object { -not $_.IsApp })
    $appReg   = @(@($RegDiff.New) + @($RegDiff.Deleted) | Where-Object { $_.IsApp })
    $othReg   = @($RegDiff.New  | Where-Object { -not $_.IsApp })

    # Hidden-noise total computed up front (needed by both the app summary and the NoiseOnly view).
    $hidden = [int]$FileDiff.NoiseCount + [int]$RegDiff.NoiseCount
    foreach ($hc in $catLabel.Keys) { if ($Diff[$hc]) { $hidden += @($Diff[$hc].Noise).Count } }
    # ---- APPLICATION (whole app section skipped when -NoiseOnly = "show me only the ignored junk") ----
    if (-not $NoiseOnly) {
    $L.Add('=================== APPLICATION ===================')
    if ($Un) {
        $L.Add("Name        : $($Un.DisplayName) $($Un.DisplayVersion)")
        if ("$($Un.Publisher)".Trim())  { $L.Add("Publisher   : $($Un.Publisher)") }
        if ($Un.ProductCode)            { $L.Add("ProductCode : $($Un.ProductCode)") }
        if ("$($Un.Uninstall)".Trim())  { $L.Add("Uninstall   : $($Un.Uninstall)") }
    } else { $L.Add('(No Add/Remove entry matched the app - check the PROGRAMS section below; the installer may register a different display name.)') }

    # ---- CHANGES BY CATEGORY (summary counts) ----
    $L.Add(''); $L.Add('================ CHANGES BY CATEGORY ================')
    $L.Add(("  {0,-22}: {1}" -f 'Files & Folders', ($appFiles.Count + $othFiles.Count)))
    $L.Add(("  {0,-22}: {1}" -f 'Registry', ($appReg.Count + $othReg.Count)))
    foreach ($cat in $catLabel.Keys) { $c = if ($Diff[$cat]) { @($Diff[$cat].Added).Count } else { 0 }; $L.Add(("  {0,-22}: {1}" -f $catLabel[$cat], $c)) }
    $L.Add(("  {0,-22}: {1}" -f 'Environment variables', $EnvChanges.Count))

    # ---- FILES & FOLDERS ----
    if (_showCat 'Files') {
        $afF = @($appFiles | Where-Object { _hit $_.Path }); $ofF = @($othFiles | Where-Object { _hit $_.Path })
        if (-not $sx -or $afF.Count -or $ofF.Count) {
            $L.Add(''); $L.Add('==================== FILES & FOLDERS ===================='); $L.Add('   (grouped by FOLDER; folders with <=3 files are expanded)')
            if ($afF.Count) { $L.Add("  Application ($($afF.Count) file(s)):"); _emitFolders $afF }
            if ($ofF.Count) { $L.Add("  Other / prerequisites ($($ofF.Count) file(s)):"); _emitFolders $ofF }
            if (-not $afF.Count -and -not $ofF.Count) { $L.Add('   (none)') }
        }
    }

    # ---- REGISTRY ----
    if (_showCat 'Registry') {
        $arR = @($appReg | Where-Object { _hit $_.Path }); $orR = @($othReg | Where-Object { _hit $_.Path })
        if (-not $sx -or $arR.Count -or $orR.Count) {
            $L.Add(''); $L.Add('====================== REGISTRY ======================'); $L.Add('   (each KEY, then the value(s) that changed inside it: name = data [type])')
            if ($arR.Count) { $L.Add("  Application ($($arR.Count)):"); _emitReg $arR }
            if ($orR.Count) { $L.Add("  Other ($($orR.Count)):"); _emitReg $orR }
            if (-not $arR.Count -and -not $orR.Count) { $L.Add('   (none)') }
        }
    }

    # ---- the small categories: ALL added items (noise already filtered out by Compare) ----
    foreach ($cat in $catLabel.Keys) {
        if (-not (_showCat $cat)) { continue }
        if (-not $Diff[$cat]) { continue }
        $items = @(@($Diff[$cat].Added) | Where-Object { _hit (_itemLine $cat $_) })
        if (-not $items.Count) { continue }
        $L.Add(''); $L.Add("==================== $($catLabel[$cat]) ====================")
        foreach ($a in $items) { $L.Add("   ADDED     $(_itemLine $cat $a)") }
    }

    # ---- ENVIRONMENT ----
    if (_showCat 'Environment') {
        $envF = @($EnvChanges | Where-Object { _hit "$($_.Name) = $($_.New)" })
        if ($envF.Count) {
            $L.Add(''); $L.Add('================ ENVIRONMENT VARIABLES ================')
            foreach ($e in $envF) { $L.Add("   $(if("$($e.Change)" -eq 'changed'){'MODIFIED'}else{'ADDED   '})  $($e.Name) = $($e.New)") }
        }
    }
    # ---- hidden noise count ----
    if ($hidden) { $L.Add(''); $L.Add("($hidden background / OS / vendor item(s) hidden as noise - run on a clean VM for less)") }
    }   # end if (-not $NoiseOnly)
    # ---- IGNORED / NOISE (the items filtered out, so the user can verify nothing real was hidden). Shown when the
    # caller asks for the full report (-IncludeNoise) or ONLY the ignored set (-NoiseOnly, the "see ignored junk" button). ----
    if (($IncludeNoise -or $NoiseOnly) -and $hidden) {
        $L.Add(''); $L.Add('############### IGNORED (filtered as OS / vendor / churn noise) ###############')
        $L.Add('# Listed so you can confirm nothing app-relevant was hidden. If something here IS the app, add it back via "Exclude item..." or the editor.')
        $nf = @($FileDiff.NoiseItems); if ($nf.Count) { $L.Add(''); $L.Add("  FILES ($($nf.Count)$(if([int]$FileDiff.NoiseCount -gt $nf.Count){" of $($FileDiff.NoiseCount), capped"})):"); _emitFolders $nf }
        $nr = @($RegDiff.NoiseItems);  if ($nr.Count) { $L.Add(''); $L.Add("  REGISTRY ($($nr.Count)$(if([int]$RegDiff.NoiseCount -gt $nr.Count){" of $($RegDiff.NoiseCount), capped"})):"); _emitPaths $nr }
        foreach ($cat in $catLabel.Keys) {
            $cn = if ($Diff[$cat]) { @($Diff[$cat].Noise) } else { @() }
            if ($cn.Count) { $L.Add(''); $L.Add("  $($catLabel[$cat]) ($($cn.Count)):"); foreach ($a in $cn) { $L.Add("      $(_itemLine $cat $a)") } }
        }
    }
    return ($L -join "`r`n")
}

# Turn a user-typed EXCLUSION (a file / folder / registry key / shortcut to NOT keep) into the PSADT v4 removal
# command that gets written into POST-INSTALLATION. Auto-detects the type. Returns @{ Label; Command; Note }.
function Get-ExclusionCommand {
    param([string]$Item)
    $p = "$Item".Trim(); if (-not $p) { return $null }
    if ($p -match '^(?i)(HKLM|HKCU|HKCR|HKU|HKEY_)') {
        $key = $p -replace '^(?i)(HKLM|HKCU|HKCR|HKU)\\', '$1:\'   # HKLM\... -> HKLM:\... (PSADT-friendly)
        return @{ Label="Exclude registry key: $p"; Command="Remove-ADTRegistryKey -Key '$key'   # excluded registry key"; Note="Custom exclusion: registry key '$p'." }
    }
    if ($p -match '(?i)\.lnk$') { return @{ Label="Exclude shortcut: $p"; Command="Remove-ADTFile -Path $(Format-PBPathArg $p)   # excluded shortcut"; Note="Custom exclusion: shortcut '$p'." } }
    if ($p -match '\\$' -or ($p -match '\\' -and $p -notmatch '\.[A-Za-z0-9]{1,6}$')) {
        return @{ Label="Exclude folder: $p"; Command="Remove-ADTFolder -Path $(Format-PBPathArg $p)   # excluded folder"; Note="Custom exclusion: folder '$p'." }
    }
    return @{ Label="Exclude file: $p"; Command="Remove-ADTFile -Path $(Format-PBPathArg $p)   # excluded file"; Note="Custom exclusion: file '$p'." }
}

# Open ONE captured certificate directly in the Windows certificate viewer (so a validator can SEE exactly which
# cert the installer added, not just browse certmgr). Exports it from its store by thumbprint to a temp .cer and
# launches it. $Store e.g. 'Root','TrustedPublisher'; $Thumbprint from the Certificates diff item Id.
function Open-CapturedCertificate {
    param([string]$Store, [string]$Thumbprint)
    foreach ($loc in 'LocalMachine','CurrentUser') {
        try {
            $cert = Get-ChildItem -Path "Cert:\$loc\$Store\$Thumbprint" -ErrorAction SilentlyContinue
            if ($cert) {
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ("pbcert_$Thumbprint.cer")
                [IO.File]::WriteAllBytes($tmp, $cert.Export('Cert'))
                Start-Process $tmp
                return $true
            }
        } catch {}
    }
    return $false
}

# From the diff, pick the app's own new Uninstall entry (by name match) and derive what we need for the script:
# the UNINSTALL command, product code (if the key is a GUID), DisplayName/Version for detection.
function Get-UninstallFromSnapshotDiff {
    param($Diff, [string]$AppName)
    $cands = @($Diff.Programs.Added) + @($Diff.Programs.Noise)   # the app's entry may have matched a noise token; still consider it
    if (-not $cands.Count) { return $null }
    $appN = ("$AppName" -replace '[^A-Za-z0-9]', '').ToLower()
    # BEST-match scoring (not first-match): exact name = 3, contains = 2; +1 when the ARP key is a GUID (ProductCode).
    # With several matching entries, the MOST-matched one drives detection/SoftIdent (user rule); ties prefer the GUID.
    $score = { param($c)
        $dn = ("$($c.Info.DisplayName)" -replace '[^A-Za-z0-9]', '').ToLower()
        if (-not $appN -or -not $dn) { return 0 }
        $s = 0
        if ($dn -eq $appN) { $s = 3 } elseif ($dn -like "*$appN*" -or $appN -like "*$dn*") { $s = 2 }
        if ($s -gt 0 -and "$($c.Info._key)" -match '^\{[0-9A-Fa-f-]{36}\}$') { $s++ }
        return $s
    }
    $pick = $null; $best = 0
    foreach ($c in $cands) { $s = & $score $c; if ($s -gt $best) { $best = $s; $pick = $c } }
    if (-not $pick) { $pick = @($Diff.Programs.Added | Where-Object { "$($_.Info.DisplayName)".Trim() } | Select-Object -First 1) }
    if (-not $pick) { return $null }
    $key = "$($pick.Info._key)"
    $isGuid = $key -match '^\{[0-9A-Fa-f-]{36}\}$'
    # ALL APPLICABLE uninstalls: the app's OWN new ARP entries (Added - OS/vendor noise like VC++/.NET is already
    # filtered out into Noise) that have an uninstall string OR a GUID key, PLUS the matched primary if it isn't
    # among them. A suite/app-with-components yields several - the package must remove EACH (uninstall-reverse).
    $allU = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    # Shared Microsoft runtimes a suite may bundle - SHOW them in the report (they're new ARP entries) but DON'T
    # auto-uninstall them (other apps depend on them). The app's own components (incl. Sentinel HASP) are kept.
    $sharedRe = '(?i)visual c\+\+|vcredist|redistributable|\.net (framework|runtime|core|sdk)|webview2|sql server (native|system clr)|windows (software development|sdk)|directx'
    $addEntry = {
        param($c)
        if (-not $c) { return }
        if ("$($c.Info.DisplayName)" -match $sharedRe) { return }   # shared MS runtime -> never auto-uninstall
        $k = "$($c.Info._key)"; $g = ($k -match '^\{[0-9A-Fa-f-]{36}\}$')
        $u = if ("$($c.Info.QuietUninstallString)".Trim()) { "$($c.Info.QuietUninstallString)" } else { "$($c.Info.UninstallString)" }
        if (-not "$u".Trim() -and $g) { $u = "MsiExec.exe /X$k /qn" }   # GUID with no string -> synthesize
        if (-not "$u".Trim()) { return }
        # A REAL uninstall command is msiexec / a GUID / an UNINSTALL-looking exe (uninstall.exe, unins000.exe,
        # uninst, remove...). A NORMAL app exe registered as "UninstallString" (launcher/updater entries do this) must
        # NOT become the package's uninstall - skip it and say so (user rule).
        $looksReal = $g -or ($u -match '(?i)msiexec') -or ($u -match '(?i)\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}') -or ($u -match '(?i)unins|uninstal|remove')
        if (-not $looksReal) { Write-Log "Snapshot: '$($c.Info.DisplayName)' uninstall string is a NORMAL exe ($u) - skipped (not an uninstaller; launcher/updater entry?)." Warning; return }
        if ($seen.ContainsKey($k.ToLower())) { return }
        $seen[$k.ToLower()] = $true
        $allU.Add([pscustomobject]@{ DisplayName="$($c.Info.DisplayName)"; ProductCode=$(if($g){$k}else{''}); Raw="$u" })
    }
    foreach ($c in @($Diff.Programs.Added)) { & $addEntry $c }
    & $addEntry $pick   # include the matched primary even if it sat in Noise (vendor-on-noise-list case)
    # .ToArray() (NOT @($allU)) - @()/index on a List[object] of PSObjects throws "Argument types do not match" in
    # PS 5.1 (memory ps51-list-object-wrap).
    $allArr = $allU.ToArray()
    # Uninstall block: the primary's command when there's one; ALL of them (uninstall-reverse) when several.
    $primaryRaw = $(if ("$($pick.Info.QuietUninstallString)".Trim()) { "$($pick.Info.QuietUninstallString)" } else { "$($pick.Info.UninstallString)" })
    if (-not "$primaryRaw".Trim() -and $isGuid) { $primaryRaw = "MsiExec.exe /X$key /qn" }
    $uninstall = if ($allArr.Count -gt 1) {
        # reverse so the last-listed (often the dependent component) uninstalls first
        (($allArr[($allArr.Count-1)..0]) | ForEach-Object { $_.Raw }) -join "`r`n"
    } else { "$primaryRaw" }
    # ProductCode for detection/SoftIdent: the primary's GUID key; if the primary's key ISN'T a GUID (EXE-type entry)
    # but another NAME-MATCHING entry has one, use THAT (user rule: "if product code is there for exe type also then it
    # should match ... most matched one ... used for soft ident").
    $pc = if ($isGuid) { $key } else { '' }
    if (-not $pc) {
        foreach ($c in $cands) {
            if ((& $score $c) -ge 2 -and "$($c.Info._key)" -match '^\{[0-9A-Fa-f-]{36}\}$') { $pc = "$($c.Info._key)"; break }
        }
    }
    return [ordered]@{
        DisplayName  = "$($pick.Info.DisplayName)"
        DisplayVersion = "$($pick.Info.DisplayVersion)"
        Publisher    = "$($pick.Info.Publisher)"
        ProductCode  = $pc
        Uninstall    = $uninstall
        AllUninstalls= $allArr
        UninstallCount = $allArr.Count
        RegKey       = $key
        Hive         = "$($pick.Info._root)"
    }
}

# From the diff, derive the actionable "cleanup" customisations a packager usually applies (disable auto-update
# service/task, remove desktop shortcut / autostart). Returns objects { Kind; Label (checkbox); Note (review text);
# Default (ticked?) }. Only the app's OWN added items (Added, not Noise) are considered. Auto-update items default
# to ticked (the package must own the version); a desktop shortcut defaults to ticked (standard cleanup); a plain
# service or autostart defaults to UN-ticked (informational - let the packager decide).
function Get-SnapshotCleanups {
    param($Diff, [string]$AppName, $FileDiff, $EnvChanges)
    $out = New-Object System.Collections.Generic.List[object]
    $isUpd = '(?i)update|updater|upgrade|autoupdate|auto-update'
    foreach ($s in @($Diff.Services.Added)) {
        $nm = "$($s.Info.DisplayName)"; if (-not $nm.Trim()) { $nm = "$($s.Id)" }
        $svcName = "$($s.Id)"
        $isUpdate = ($nm -match $isUpd) -or ("$($s.Info.Path)" -match $isUpd)
        $out.Add([pscustomobject]@{
            Kind='Service'; Default=[bool]$isUpdate; Label="Disable service: $nm"
            Command="Stop-Service -Name '$svcName' -Force -ErrorAction SilentlyContinue; Set-Service -Name '$svcName' -StartupType Disabled -ErrorAction SilentlyContinue   # disable service '$nm'"
            Note="Installer created service '$nm' ($svcName)$(if($isUpdate){' - looks like an AUTO-UPDATE service; disable it so the package owns the version'}else{''})."
        })
    }
    foreach ($t in @($Diff.Tasks.Added)) {
        $nm = "$($t.Info.Name)"; $isUpdate = ($nm -match $isUpd)
        $out.Add([pscustomobject]@{
            Kind='Task'; Default=[bool]$isUpdate; Label="Remove scheduled task: $nm"
            Command="Unregister-ScheduledTask -TaskName '$nm' -TaskPath '$($t.Info.Path)' -Confirm:`$false -ErrorAction SilentlyContinue   # unregister scheduled task '$nm'"
            Note="Installer created scheduled task '$nm'$(if($isUpdate){' - looks like an AUTO-UPDATE task; remove it so the package owns the version'}else{''})."
        })
    }
    foreach ($r in @($Diff.RunKeys.Added)) {
        $nm = "$($r.Info.Name)"
        $out.Add([pscustomobject]@{
            Kind='RunKey'; Default=$true; Label="Remove autostart: $nm"
            Command="Remove-ADTRegistryKey -Key '$($r.Info.Hive)' -Name '$nm'   # remove autostart (Run key) '$nm'"
            Note="Installer added autostart (Run key) '$nm' = $($r.Info.Command)."
        })
    }
    foreach ($sc in @($Diff.Shortcuts.Added)) {
        $id = "$($sc.Id)"; $nm = "$($sc.Info.Name)"; if (-not "$nm".Trim()) { $nm = [IO.Path]::GetFileNameWithoutExtension($id) }
        if ($id -match '(?i)\\Desktop\\') {
            $out.Add([pscustomobject]@{
                Kind='Shortcut'; Default=$true; Label="Remove desktop shortcut: $nm"
                Command="Remove-ADTFile -Path '$id'   # remove desktop shortcut '$nm'"
                Note="Installer created a DESKTOP shortcut '$nm'."
            })
        } elseif ($nm -match '(?i)uninstall|uninst|\bremove\b') {
            # A Start-Menu UNINSTALL shortcut: SCCM/Intune owns removal, so users shouldn't run the vendor uninstaller.
            $out.Add([pscustomobject]@{
                Kind='Shortcut'; Default=$true; Label="Remove uninstall shortcut: $nm"
                Command="Remove-ADTFile -Path '$id'   # remove Start-Menu uninstall shortcut '$nm'"
                Note="Installer created a Start-Menu UNINSTALL shortcut '$nm' - removed so users can't run the vendor uninstaller directly (SCCM/Intune manages removal)."
            })
        }
        # a normal Start-Menu app shortcut is expected -> not flagged
    }
    # POST-UNINSTALL cleanups, tagged '# [post-uninstall]' so the build routes them to the POST-UNINSTALLATION section
    # (NOT post-install): removing a cert/driver at INSTALL time would break the app - they're cleaned up only when the
    # package is removed, so the package leaves nothing behind.
    foreach ($c in @($Diff.Certificates.Added)) {
        $thumb = (@("$($c.Id)" -split '\\'))[-1]; $store = "$($c.Info.Store)"; $subj = "$($c.Info.Subject)"
        if (-not "$thumb".Trim()) { continue }
        $out.Add([pscustomobject]@{
            Kind='Certificate'; Default=$true; Label="Remove certificate on uninstall: $subj ($store)"
            Command="Remove-Item -LiteralPath 'Cert:\LocalMachine\$store\$thumb' -Force -ErrorAction SilentlyContinue   # [post-uninstall] remove certificate '$subj' (LocalMachine\$store) added by this install"
            Note="Installer added certificate '$subj' to LocalMachine\$store - auto-removed on UNINSTALL so the package cleans up after itself."
        })
    }
    foreach ($d in @($Diff.Drivers.Added)) {
        $folder = "$($d.Id)"; if (-not "$folder".Trim()) { continue }
        $infName = ($folder -replace '(?i)\.inf_.*$', '')     # 'heci.inf_amd64_abc' -> 'heci' (original INF base, NO extension)
        if (-not "$infName".Trim()) { $infName = $folder }
        $infBase = "$infName.inf"
        # The team's locale-safe Remove-PnPDrivers helper (in the PSADT extensions) handles everything - find the
        # oem*.inf by .cat match + pnputil /delete-driver /uninstall /force - so call it directly.
        $out.Add([pscustomobject]@{
            Kind='Driver'; Default=$true; Label="Remove driver on uninstall: $infBase"
            Command="Remove-PnPDrivers -Delinflist '$infName'   # [post-uninstall] remove driver '$infBase' added by this install"
            Note="Installer added a driver ($infBase) to the DriverStore - removed on UNINSTALL via the team's locale-safe Remove-PnPDrivers helper (Intune-safe: reboot codes not propagated). Untick if this driver should remain."
        })
    }
    # FONTS the install dropped in Windows\Fonts -> remove on UNINSTALL with the team's Remove-MTBFonts helper.
    $seenFont = @{}
    foreach ($f in @($FileDiff.New)) {
        $p = "$($f.Path)"
        if ($p -notmatch '(?i)\\Fonts\\[^\\]+\.(ttf|otf|ttc|fon|fnt)$') { continue }
        $fn = Split-Path $p -Leaf; if ($seenFont.ContainsKey($fn.ToLower())) { continue }; $seenFont[$fn.ToLower()] = $true
        $out.Add([pscustomobject]@{
            Kind='Font'; Default=$true; Label="Remove font on uninstall: $fn"
            Command="Remove-MTBFonts -FontName '$fn'   # [post-uninstall] remove font '$fn' added by this install"
            Note="Installer added font '$fn' to Windows\Fonts - removed on UNINSTALL via the team's Remove-MTBFonts helper."
        })
    }
    # ENVIRONMENT VARIABLES the install ADDED (new vars) -> remove on UNINSTALL. (A PATH that was only APPENDED to is
    # left for the packager - blindly removing a shared PATH segment is risky; flagged via the note.)
    foreach ($e in @($EnvChanges)) {
        if ("$($e.Change)" -ne 'added') { continue }
        $full = "$($e.Name)"; $scope = if ($full -match '^(?i)MACHINE\\') { 'Machine' } else { 'User' }
        $vn = ($full -replace '^(?i)(MACHINE|USER)\\', '')
        if (-not "$vn".Trim() -or $vn -match '(?i)^Path$') { continue }   # skip PATH (append-only) - too risky to auto-remove
        $out.Add([pscustomobject]@{
            Kind='EnvVar'; Default=$true; Label="Remove env var on uninstall: $vn ($scope)"
            Command="Remove-ADTEnvironmentVariable -Variable '$vn' -Target '$scope'   # [post-uninstall] remove env var '$vn' added by this install"
            Note="Installer added $scope environment variable '$vn' = $($e.New) - removed on UNINSTALL."
        })
    }
    return $out.ToArray()
}

#region Uninstall leftovers + snapshot report persistence ------------------------------------------------------------
# UNINSTALL LEFTOVER CHECK (plan A) - the SMART version: instead of a second full machine snapshot pair, we already
# KNOW exactly what the install created (the install snapshot diff). After the user manually UNINSTALLS the app, a
# LIVE Test-Path over those known items tells us precisely what the uninstaller LEFT BEHIND - zero noise, zero new
# scanning, only items related to THIS application. The result becomes PSADT v4 POST-UNINSTALLATION cleanup commands
# (Remove-ADTFolder / Remove-ADTFile / Remove-ADTRegistryKey) incl. now-EMPTY folders, routed through the existing
# '# [post-uninstall]' pipe.

# Compact, JSON-safe candidate list of everything the INSTALL created (persisted with the report, so the leftover
# check also works on a LOADED report / after reopening the tool).
function Get-LeftoverCandidates {
    param($Diff, $FileDiff, $RegDiff, [string]$Vendor, [string]$App)
    $files = @(@($FileDiff.New) | Where-Object { $_.IsApp } | ForEach-Object { "$($_.Path)" } | Select-Object -First 4000)
    $dirs  = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($Diff.ProgramDirs.Added)) { $p = "$($d.Id)"; if ($p) { $dirs.Add($p) } }
    # ...plus the distinct parent folders of the app's files (the created tree may be deeper than ProgramDirs records).
    foreach ($p in @($files | ForEach-Object { Split-Path $_ -Parent } | Sort-Object -Unique | Select-Object -First 200)) { if ($p -and -not $dirs.Contains($p)) { $dirs.Add($p) } }
    $reg = @(@($RegDiff.New) | Where-Object { $_.IsApp } | ForEach-Object { "$($_.Path)" } | Select-Object -First 2000)
    $lnk = @(@($Diff.Shortcuts.Added) | ForEach-Object { "$($_.Id)" } | Where-Object { $_ })
    # FULL install footprint (app + bundled PREREQUISITES like VC++) - so the after-uninstall diff can show whether EVERY
    # installed thing (not just the app's own) is still present / removed. These drive the DIFF VIEW only; the actionable
    # cleanup (Files/Dirs/Reg/Lnk above) stays app-only so we never offer to remove a shared runtime.
    $allFiles = @(@($FileDiff.New) | ForEach-Object { "$($_.Path)" } | Select-Object -First 5000)
    $allReg   = @(@($RegDiff.New)  | ForEach-Object { "$($_.Path)" } | Select-Object -First 3000)
    # Vendor/App names persist too: the leftover check ALSO sweeps the standard data roots for RUNTIME-created
    # folders/keys named after them (data the app wrote at first run / during testing, which the install diff can't know).
    return @{ Files = @($files); Dirs = @($dirs); Reg = @($reg); Lnk = @($lnk); AllFiles = @($allFiles); AllReg = @($allReg); Vendor = "$Vendor"; App = "$App" }
}

# Turn a LITERAL path into a PSADT-env-variable path + ready-to-embed quoted argument (team convention: never hardcode
# C:\Program Files etc. - use $envProgramFiles/$envProgramData/... so the package works on any layout/bitness/locale).
# Longest prefixes first (Public Desktop / Start Menu before ProgramData; ProgramFiles(x86) before ProgramFiles).
# Returns the quoted arg: DOUBLE-quoted when an $env var was substituted (it must expand), single-quoted otherwise.
function Format-PBPathArg {
    param([string]$Path)
    $p = "$Path".TrimEnd('\')
    $maps = @(
        @{ V = [Environment]::GetFolderPath('CommonDesktopDirectory'); T = '$envCommonDesktopDirectory' }
        @{ V = [Environment]::GetFolderPath('CommonPrograms');         T = '$envCommonStartMenuPrograms' }
        @{ V = [Environment]::GetFolderPath('CommonStartMenu');        T = '$envCommonStartMenu' }
        @{ V = ${env:ProgramFiles(x86)};                               T = '$envProgramFilesX86' }
        @{ V = $env:ProgramFiles;                                      T = '$envProgramFiles' }
        @{ V = $env:ProgramData;                                       T = '$envProgramData' }
        @{ V = $env:LOCALAPPDATA;                                      T = '$envLocalAppData' }
        @{ V = $env:APPDATA;                                           T = '$envAppData' }
        @{ V = $env:windir;                                            T = '$envWinDir' }
    )
    foreach ($m in $maps) {
        $v = "$($m.V)".TrimEnd('\')
        if (-not $v) { continue }
        if ($p -ieq $v) { return "`"$($m.T)`"" }
        if ($p.StartsWith($v + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return "`"$($m.T)$($p.Substring($v.Length))`""
        }
    }
    return "'$p'"
}

# Normalize any registry-key spelling to BOTH the provider form (Registry::HKEY_...) for Test-Path and the PSADT
# drive form (HKLM:\...) for the generated command. Returns $null for unrecognizable input.
function ConvertTo-PBRegForms {
    param([string]$Key)
    $k = "$Key".Trim() -replace '^Registry::', ''
    $map = @{ 'HKLM' = 'HKEY_LOCAL_MACHINE'; 'HKCU' = 'HKEY_CURRENT_USER'; 'HKU' = 'HKEY_USERS'; 'HKCR' = 'HKEY_CLASSES_ROOT' }
    foreach ($short in $map.Keys) {
        if ($k -match "(?i)^$short(:)?\\") { $k = $map[$short] + $k.Substring($k.IndexOf('\')) ; break }
    }
    if ($k -notmatch '(?i)^HKEY_') { return $null }
    $drive = $k
    foreach ($short in $map.Keys) { $drive = $drive -replace ("(?i)^" + $map[$short] + '\\'), ($short + ':\') }
    return @{ Provider = "Registry::$k"; Drive = $drive }
}

# LIVE leftover check - run AFTER the user manually uninstalled the app. Returns items ready for the exclusion
# checklist: @{ Label; Command; Note; Kind } - commands tagged '# [post-uninstall]' so Apply routes them into the
# package's POST-UNINSTALLATION (the existing pipe). De-duplicated: a leftover FOLDER swallows its files/subkeys.
function Get-UninstallLeftovers {
    param([Parameter(Mandatory)]$Candidates, [int]$MaxItems = 60, [string[]]$DataRoots)
    $items = New-Object System.Collections.Generic.List[object]
    $tag = '# [post-uninstall] uninstall-leftover'
    # Windows \Recent\ (recently-used shortcuts) is user MRU churn, never app data - never a cleanup candidate.
    $isJunk = '(?i)\\Recent(\\|$)'
    # 1. Folders first (longest-path wins are collapsed into their top-most leftover ancestor).
    $liveDirs = @(@($Candidates.Dirs) | Where-Object { $_ -and ($_ -notmatch $isJunk) -and (Test-Path -LiteralPath $_ -PathType Container) } | Sort-Object { $_.Length })
    $topDirs = New-Object System.Collections.Generic.List[string]
    foreach ($d in $liveDirs) {
        $under = $false; foreach ($t in $topDirs) { if ($d.StartsWith(($t.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { $under = $true; break } }
        if (-not $under) { $topDirs.Add($d) }
    }
    foreach ($d in $topDirs) {
        $empty = (@(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue).Count -eq 0)
        $items.Add(@{ Kind = 'Folder'; Label = "Leftover folder$(if ($empty) { ' (EMPTY)' }): $d"; Command = "Remove-ADTFolder -Path $(Format-PBPathArg $d)  $tag"
                      Note  = if ($empty) { 'The uninstaller left this folder behind empty - safe to remove.' } else { 'The uninstaller left this folder (and its contents) behind.' } })
    }
    # 2. Files NOT already covered by a leftover folder.
    foreach ($f in @($Candidates.Files)) {
        if (-not $f -or ($f -match $isJunk) -or -not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $covered = $false; foreach ($t in $topDirs) { if ($f.StartsWith(($t.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break } }
        if ($covered) { continue }
        $items.Add(@{ Kind = 'File'; Label = "Leftover file: $f"; Command = "Remove-ADTFile -Path $(Format-PBPathArg $f)  $tag"; Note = 'The uninstaller left this file behind.' })
    }
    # 3. Shortcuts (a leftover .lnk after uninstall is always junk) - except Windows \Recent\ MRU shortcuts.
    foreach ($l in @($Candidates.Lnk)) {
        if ($l -and ($l -notmatch $isJunk) -and (Test-Path -LiteralPath $l -PathType Leaf)) {
            $items.Add(@{ Kind = 'Shortcut'; Label = "Leftover shortcut: $l"; Command = "Remove-ADTFile -Path $(Format-PBPathArg $l)  $tag"; Note = 'Shortcut left behind after uninstall.' })
        }
    }
    # 4. Registry keys, collapsed to their top-most leftover key.
    $liveReg = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($Candidates.Reg)) {
        $forms = ConvertTo-PBRegForms -Key $r
        if ($forms -and (Test-Path -LiteralPath $forms.Provider -ErrorAction SilentlyContinue)) { $liveReg.Add($forms) }
    }
    $topReg = New-Object System.Collections.Generic.List[object]
    foreach ($r in ($liveReg | Sort-Object { $_.Provider.Length })) {
        $under = $false; foreach ($t in $topReg) { if ($r.Provider.StartsWith(($t.Provider.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { $under = $true; break } }
        if (-not $under) { $topReg.Add($r) }
    }
    foreach ($r in $topReg) {
        $items.Add(@{ Kind = 'Registry'; Label = "Leftover registry key: $($r.Drive)"; Command = "Remove-ADTRegistryKey -Key '$($r.Drive)' -Recurse  $tag"; Note = 'The uninstaller left this key (and subkeys) behind.' })
    }
    # 5. RUNTIME DATA sweep: the app may have created data AFTER install (first run / your testing) in the standard data
    #    roots - places the install diff cannot know about. Check for top-level folders/keys NAMED EXACTLY like the
    #    app or vendor. Safety policy: APP-named -> ticked by default (belongs to this app); VENDOR-named -> reported but
    #    UNTICKED (the vendor folder may be SHARED with the vendor's other products - a human decides).
    if (-not $DataRoots) { $DataRoots = @($env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) }
    $vend = "$($Candidates.Vendor)".Trim(); $app = "$($Candidates.App)".Trim()
    $names = @()
    if ($app.Length  -ge 3) { $names += @{ N = $app;  Tick = $true } }
    if ($vend.Length -ge 3 -and ($vend -ine $app)) { $names += @{ N = $vend; Tick = $false } }
    foreach ($nm in $names) {
        foreach ($root in @($DataRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
            $p = Join-Path $root $nm.N
            if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
            $covered = $false; foreach ($t in $topDirs) { if (($p -ieq $t) -or $p.StartsWith(($t.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break } }
            if ($covered) { continue }
            $empty = (@(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue).Count -eq 0)
            $warn = if (-not $nm.Tick) { "   [VENDOR folder - may be SHARED with other $vend products; verify before ticking]" } else { '' }
            $items.Add(@{ Kind = 'RuntimeData'; Default = [bool]$nm.Tick
                          Label = "Runtime data folder$(if ($empty) { ' (EMPTY)' }): $p$warn"
                          Command = "Remove-ADTFolder -Path $(Format-PBPathArg $p)  $tag"
                          Note = if ($nm.Tick) { 'Created by the app at RUN time (not by the installer) - left behind after uninstall.' } else { "Vendor-level folder - may be shared with other $vend products; verify before ticking." } })
        }
        foreach ($rk in @("HKCU:\Software\$($nm.N)", "HKLM:\SOFTWARE\$($nm.N)")) {
            $forms = ConvertTo-PBRegForms -Key $rk
            if (-not $forms -or -not (Test-Path -LiteralPath $forms.Provider -ErrorAction SilentlyContinue)) { continue }
            $covered = $false; foreach ($t in $topReg) { if (($forms.Provider -ieq $t.Provider) -or $forms.Provider.StartsWith(($t.Provider.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break } }
            if ($covered) { continue }
            $warn = if (-not $nm.Tick) { "   [VENDOR key - may be SHARED; verify before ticking]" } else { '' }
            $items.Add(@{ Kind = 'RuntimeData'; Default = [bool]$nm.Tick
                          Label = "Runtime registry key: $($forms.Drive)$warn"
                          Command = "Remove-ADTRegistryKey -Key '$($forms.Drive)' -Recurse  $tag"
                          Note = if ($nm.Tick) { 'Created by the app at RUN time - left behind after uninstall.' } else { "Vendor-level key - may be shared with other $vend products; verify before ticking." } })
        }
    }
    $out = @($items | Select-Object -First $MaxItems)
    if ($items.Count -gt $MaxItems) { Write-Log "Leftover check: $($items.Count) leftover item(s) found - showing the first $MaxItems (top-most folders/keys already swallow their children)." Warning }
    return $out
}

# AFTER-UNINSTALL change set - the reliability view the user wants: a real before(=install state)/after diff of the app's
# footprint, rendered by the SAME tree as the install diff. Built LIVE from the install candidates + Test-Path (so it works
# same-session AND on a loaded report, no stored after-install snapshot needed):
#   REMOVED (red)   = an install-created file/key the uninstaller cleaned up (good)
#   LEFT BEHIND (amber, 'modified') = an install-created file/key still on disk/registry (tick to clean)
#   ADDED (green)   = a NEW file under the app's install folders the install did not create (post-install data / junk)
function New-UninstallChangeSet {
    param($Candidates, [string]$AppName = '', [int]$MaxAdded = 500)
    $cs = [ordered]@{ App = "$AppName - after uninstall"; When = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Counts = @{ new=0; modified=0; deleted=0 }
                      Files = @(); Registry = @(); RegValues = @{}; Lists = [ordered]@{}; Env = @(); Noise = @() }
    # Diff the FULL install footprint (app + prereqs) when available, so VC++ etc. show removed/left too; fall back to
    # the app-only file list for older/loaded reports that predate AllFiles.
    $srcFiles = if (@($Candidates.AllFiles | Where-Object { $_ }).Count) { @($Candidates.AllFiles | Where-Object { $_ }) } else { @($Candidates.Files) }
    $srcReg   = if (@($Candidates.AllReg   | Where-Object { $_ }).Count) { @($Candidates.AllReg   | Where-Object { $_ }) } else { @($Candidates.Reg) }
    $files = New-Object System.Collections.Generic.List[object]
    $instSet = @{}; foreach ($p in $srcFiles) { if ($p) { $instSet["$p"] = $true } }
    foreach ($p in $srcFiles) {
        if (-not $p) { continue }
        if (Test-Path -LiteralPath $p) { $files.Add(@{ Path="$p"; Change='modified' }); $cs.Counts.modified++ }   # LEFT BEHIND
        else { $files.Add(@{ Path="$p"; Change='deleted' }); $cs.Counts.deleted++ }                                # removed by uninstaller
    }
    # ADDED after uninstall: new files under the app's install dirs the install did NOT create.
    $addN = 0
    foreach ($ad in @($Candidates.Dirs)) {
        if ($addN -ge $MaxAdded -or -not $ad -or -not (Test-Path -LiteralPath $ad -PathType Container)) { continue }
        try { foreach ($fi in @(Get-ChildItem -LiteralPath $ad -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            if ($addN -ge $MaxAdded) { break }
            if (-not $instSet.ContainsKey($fi.FullName)) { $files.Add(@{ Path=$fi.FullName; Change='new' }); $cs.Counts.new++; $addN++ }
        } } catch {}
    }
    $cs.Files = $files.ToArray()
    $regs = New-Object System.Collections.Generic.List[object]
    foreach ($k in @($Candidates.Reg)) {
        if (-not $k) { continue }
        $forms = ConvertTo-PBRegForms -Key $k
        if ($forms -and (Test-Path -LiteralPath $forms.Provider -ErrorAction SilentlyContinue)) { $regs.Add(@{ Path="$k"; Change='modified' }); $cs.Counts.modified++ }
        else { $regs.Add(@{ Path="$k"; Change='deleted' }); $cs.Counts.deleted++ }
    }
    $cs.Registry = $regs.ToArray()
    $sc = @()
    foreach ($l in @($Candidates.Lnk)) { if ($l -and (Test-Path -LiteralPath $l -PathType Leaf)) { $sc += @{ Label=[IO.Path]::GetFileNameWithoutExtension("$l"); Fields=[ordered]@{ Path="$l" } }; $cs.Counts.modified++ } }
    if ($sc.Count) { $cs.Lists['Shortcuts left behind'] = $sc }
    return $cs
}

# Persist / restore the whole snapshot result (report text, exclusions, shortcuts, per-user data, leftover candidates)
# as JSON in the work folder - so a packager can CLOSE the tool and later LOAD the report to re-apply actions, run the
# leftover check, or screenshot the shortcuts, without re-running the installer snapshot.
function Save-SnapshotState {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Data)
    try {
        $dir = Split-Path $Path -Parent; if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
        $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
        Write-Log "Snapshot report saved: $Path"
        return $true
    } catch { Write-Log "Could not save the snapshot report ($Path): $($_.Exception.Message)" Warning; return $false }
}
function Read-SnapshotState {
    param([Parameter(Mandatory)][string]$Path)
    try { return ((Get-Content -LiteralPath $Path -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json) }
    catch { Write-Log "Could not load the snapshot report ($Path): $($_.Exception.Message)" Warning; return $null }
}
#endregion

