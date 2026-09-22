##############################################################
# Screenshots.ps1
# Launch the REAL Start-Menu shortcuts an app installs and screenshot the running app, for visual validation.
# DIFFERENTIATION (which shortcuts are THIS app's), most-reliable first:
#   1. snapshot reference  - exact target .exe / install folder captured by the before/after snapshot
#   2. install timestamp   - .lnk files created AT/AFTER the app's install time (the user's idea: no name guessing)
#   3. app name tokens     - vendor/app from the package name (last resort)
#   ...and NEVER "launch everything" when there's no signal (it returns nothing + says why).
# Saves PNGs (each CAPTIONED with its shortcut name) + an index.html contact sheet to a LOCAL work folder only.
# Best-effort: a shortcut that won't launch / show a window is logged and skipped; bounded timeouts; security/EDR
# products are refused (re-launching them is blocked anyway).
##############################################################

# Names/targets that are NOT the real app (so we never launch an uninstaller/updater/help/doc link). NOTE: 'license'
# and 'support' are qualified with a negative lookahead so a real TOOL like "Licence Manager" / "Support Console" is
# NOT dropped - only doc/agreement-style entries ("License Agreement", "Support (website)") are. Likewise 'manual'
# only excludes a documentation manual, not a word inside a real name.
$script:ShortcutExcludeRe = '(?i)uninstall|uninst|\bremove\b|\bupdate\b(?!\s*(manager|center|tool))|upgrade|repair|\bmodify\b|readme|read ?me|\bhelp\b|user manual|\bmanual\b(?!\s*(entry|mode))|documentation|website|home ?page|release ?notes|licen[cs]e(?!\s*(manager|server|admin|console|tool|service|daemon|key))|changelog|whats ?new|\bsupport\b(?!\s*(tool|manager|console|assistant|center|app))|\bactivation\b(?!\s*(tool|manager))|\bdemo\b'

# Resolve a .lnk to its target/args/workdir/icon via WScript.Shell. $null on failure.
function Resolve-ShortcutTarget {
    param([string]$LnkPath)
    if (-not $LnkPath -or -not (Test-Path -LiteralPath $LnkPath)) { return $null }
    $sh = $null
    try {
        $sh  = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($LnkPath)
        return @{ Target = "$($lnk.TargetPath)"; Args = "$($lnk.Arguments)"; WorkDir = "$($lnk.WorkingDirectory)"; Icon = "$($lnk.IconLocation)" }
    } catch { return $null }
    finally { if ($sh) { try { [Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null } catch {} } }
}

# WHEN did the package install run? Use the package's OWN PSADT install log (ProgramData\VWG\Logs\<package>\
# *install*.log). That folder is named after the PACKAGE (the tool's own convention), so it's a reliable, name-
# independent signal - unlike the installed app's ARP DisplayName or its install folder, which vendors name
# arbitrarily and often do NOT match the package name. Returns @{ Start; End; Source } or $null:
#   Start = log creation (install began), End = log last write (install finished). Shortcuts created in that
#   window are what THIS install created, whatever the app/exe/folder is called.
function Get-AppInstallWindow {
    param([string[]]$AppTokens, [string]$LogRoot)
    $tok = @($AppTokens | Where-Object { $_ } | ForEach-Object { $_.ToLower() })
    if (-not $tok.Count) { return $null }
    # Local ProgramData\VWG\Logs by default; -LogRoot lets a caller point at a remote machine's logs
    # (e.g. \\<host>\C$\ProgramData\VWG\Logs). PSADT log NAMES carry the metadata, e.g.
    # 'Mozilla_FirefoxESRMAN_140.12.0_x86_MUL_0001_PSAppDeployToolkit_Install.log'.
    $base = if ("$LogRoot".Trim()) { $LogRoot } else { Join-Path $env:ProgramData 'VWG\Logs' }
    if (-not (Test-Path -LiteralPath $base)) { return $null }
    try {
        # Scan ALL *.log FILES recursively (logs sit directly in the folder OR in a sub-folder - we don't rely on a
        # per-package folder name). Match by the app TOKENS appearing in the file NAME + its sub-path - so the exact
        # format doesn't matter; if we can find vendor+app(+version) we know it's ours. Tolerant of any naming.
        $all = @(Get-ChildItem -LiteralPath $base -Filter *.log -File -Recurse -ErrorAction SilentlyContinue)
        if (-not $all.Count) { return $null }
        $score = { param($f) $h = "$($f.FullName.Substring($base.Length))".ToLower(); @($tok | Where-Object { $h.Contains($_) }).Count }
        # Prefer logs where EVERY token matches (vendor AND app = reliably ours); else fall back to ANY token.
        $cand = @($all | Where-Object { (& $score $_) -eq $tok.Count })
        if (-not $cand.Count) { $cand = @($all | Where-Object { (& $score $_) -gt 0 }) }
        if (-not $cand.Count) { return $null }
        # Prefer the NEWEST INSTALL log (name says install, not uninstall); else the newest matching log of any kind.
        $inst = @($cand | Where-Object { $_.Name -match '(?i)install' -and $_.Name -notmatch '(?i)uninstall' } | Sort-Object LastWriteTime -Descending)
        $pick = if ($inst.Count) { $inst[0] } else { @($cand | Sort-Object LastWriteTime -Descending)[0] }
        $kind = if ($pick.Name -match '(?i)uninstall') { 'uninstall' } else { 'install' }
        return @{ Start = $pick.CreationTime; End = $pick.LastWriteTime; Source = "package $kind log ($($pick.Name))"; LogPath = "$($pick.FullName)" }
    } catch { return $null }
}

# The REAL app shortcuts to validate. Source = the snapshot diff (-Diff) OR a LIVE Start-Menu scan (-Live).
# Keeps only Start-Menu .lnks whose target is an .exe, drops Desktop + uninstall/update/help, dedupes true dupes.
# For -Live, identifies THIS install's shortcuts by RELIABLE, NAME-INDEPENDENT signals only:
#   1. -RefShortcuts: the exact target exe(s) a snapshot recorded (most precise), then
#   2. install WINDOW (-SinceTime/-UntilTime from the package install log): any shortcut CREATED while the install
#      ran is one it made - no matter how the app / its ARP entry / its install folder are named.
# With NEITHER signal it returns NOTHING (it will not guess by app name or launch the whole Start Menu).
# ($AppTokens is accepted only for the -Diff path's callers; it is NOT used to match live shortcuts by name.)
function Get-AppStartMenuShortcuts {
    param($Diff, [string[]]$AppTokens, [switch]$Live, [datetime]$SinceTime, [datetime]$UntilTime, [object[]]$RefShortcuts)
    $lnks = New-Object System.Collections.Generic.List[string]
    if ($Live) {
        foreach ($f in 'Programs','CommonPrograms') {
            try {
                $d = [Environment]::GetFolderPath($f)
                if ($d -and (Test-Path $d)) { Get-ChildItem -LiteralPath $d -Filter *.lnk -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $lnks.Add($_.FullName) } }
            } catch {}
        }
    } elseif ($Diff -and $Diff.Shortcuts -and $Diff.Shortcuts.Added) {
        foreach ($a in @($Diff.Shortcuts.Added)) { $id = "$($a.Id)"; if ($id -match '(?i)\.lnk$') { $lnks.Add($id) } }
    }
    # base filter -> candidate objects (with the .lnk timestamp for the SinceTime narrowing). Every drop is LOGGED
    # with its reason so "what got ignored and why" is answerable from the log (the user asked for this).
    $cands = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $skip = { param($n, $why) if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "  [shortcut] SKIP '$n' - $why" } }
    foreach ($lnk in $lnks) {
        if (-not (Test-Path -LiteralPath $lnk)) { continue }
        $name = [IO.Path]::GetFileNameWithoutExtension($lnk)
        if ($lnk -match '(?i)\\Desktop\\') { & $skip $name 'on the Desktop (desktop shortcuts are removed, not validated)'; continue }
        if ($lnk -notmatch '(?i)\\Start Menu\\Programs\\') { & $skip $name 'not under Start Menu\Programs'; continue }
        if ("$name" -match $script:ShortcutExcludeRe) { & $skip $name 'name looks like uninstall/update/help/docs (not the app itself)'; continue }
        $t = Resolve-ShortcutTarget -LnkPath $lnk
        if (-not $t -or "$($t.Target)" -notmatch '(?i)\.exe$') { & $skip $name "target is not an .exe ($(if($t){"$($t.Target)"}else{'unresolved'}))"; continue }
        if ("$($t.Target)" -match $script:ShortcutExcludeRe) { & $skip $name "target path looks like uninstall/update/help ($($t.Target))"; continue }
        $key = "$name|$($t.Target)|$($t.Args)".ToLower()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $when = $null; try { $fi = Get-Item -LiteralPath $lnk -ErrorAction Stop; $when = @($fi.CreationTime, $fi.LastWriteTime | Sort-Object -Descending)[0] } catch {}
        $cands.Add([pscustomobject]@{ Name = $name; Lnk = $lnk; Target = "$($t.Target)"; Args = "$($t.Args)"; WorkDir = "$($t.WorkDir)"; When = $when })
    }
    if (-not $Live) { return $cands.ToArray() }   # snapshot diff is already exactly the install's shortcuts

    # ---- LIVE: identify the install's shortcuts by RELIABLE, NAME-INDEPENDENT signals only ----
    # 1. Snapshot reference: the exact target exe(s) the before/after snapshot recorded - most precise.
    if ($RefShortcuts -and @($RefShortcuts).Count) {
        $refExe = @{}
        foreach ($r in @($RefShortcuts)) { $rt = "$($r.Target)".ToLower(); if ($rt) { $refExe[$rt] = $true } }
        $m = @($cands | Where-Object { $refExe.ContainsKey("$($_.Target)".ToLower()) })
        if ($m.Count) { return $m }
    }
    # 2. INSTALL WINDOW (smart, name-independent): the package's install LOG says WHEN the install ran; any
    #    Start-Menu shortcut CREATED in that window is one this install made - whatever the app/exe/folder is named.
    #    A small back-buffer + forward-margin covers clock skew and shortcuts written right at the end of install.
    if ($SinceTime -and $SinceTime -ne [datetime]::MinValue) {
        $lo = $SinceTime.AddMinutes(-2)
        $hi = if ($UntilTime -and $UntilTime -ne [datetime]::MinValue) { $UntilTime.AddMinutes(10) } else { [datetime]::MaxValue }
        $m = @($cands | Where-Object { $_.When -and $_.When -ge $lo -and $_.When -le $hi })
        if ($m.Count) { return $m }
    }
    # 3. No reliable signal (no snapshot reference, no install log) -> capture NOTHING. The caller explains why,
    #    rather than guessing by app name (unreliable) or launching every shortcut on the machine.
    return @()
}

# Difference between two shortcut sets (reference vs current), matched on name+target. Tolerates a null/empty
# reference (everything is 'Added', nothing 'Gone'). Returns @{ Added; Gone; Same }.
function Compare-ShortcutSets {
    param([object[]]$Reference, [object[]]$Current)
    $keyOf = { param($s) $k = "$($s.Name)|$($s.Target)".ToLower(); if (-not "$k".Trim('|')) { $k = "$($s.Name)$($s.Target)".ToLower() }; $k }
    $refKey = @{}; foreach ($r in @($Reference)) { $k = & $keyOf $r; if ($k) { $refKey[$k] = $r } }
    $curKey = @{}; foreach ($c in @($Current))   { $k = & $keyOf $c; if ($k) { $curKey[$k] = $c } }
    $added = New-Object System.Collections.Generic.List[object]
    $same  = New-Object System.Collections.Generic.List[object]
    $gone  = New-Object System.Collections.Generic.List[object]
    foreach ($k in $curKey.Keys) { if ($refKey.ContainsKey($k)) { $same.Add($curKey[$k]) } else { $added.Add($curKey[$k]) } }
    foreach ($k in $refKey.Keys) { if (-not $curKey.ContainsKey($k)) { $gone.Add($refKey[$k]) } }
    return @{ Added = $added.ToArray(); Gone = $gone.ToArray(); Same = $same.ToArray() }
}

# Win32 + GDI loaded once.
function Initialize-ScreenCapture {
    if (-not ('PBScreen' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class PBScreen {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint t1, uint t2, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    // Left-click at a screen point (used to open the taskbar "show hidden icons" tray flyout when UIA can't invoke it).
    public static void ClickAt(int x, int y) { SetCursorPos(x, y); mouse_event(0x0002,0,0,0,IntPtr.Zero); mouse_event(0x0004,0,0,0,IntPtr.Zero); }
    public static void PressEsc() { keybd_event(0x1B,0,0,IntPtr.Zero); keybd_event(0x1B,0,0x0002,IntPtr.Zero); }
    // GRACEFULLY close (WM_CLOSE) every visible top-level window owned by one of the given pids - dialogs INCLUDED.
    // Dismissing the app's modal dialogs while it is still ALIVE is what avoids the un-removable Windows "ghost" window
    // that a force-kill leaves behind when it terminates a process that is showing a modal dialog. Returns the count.
    public static int CloseWindowsForPids(string pidCsv) {
        var set = new HashSet<string>((pidCsv ?? "").Split(','));
        int c = 0;
        EnumWindows((h,l)=>{ try {
            if (!IsWindowVisible(h)) return true;
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (set.Contains(pid.ToString())) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); c++; }
        } catch {} return true; }, IntPtr.Zero);
        return c;
    }
    // WM_CLOSE a single window by handle (used by the title-based cleanup fallback).
    public static void CloseWindow(IntPtr h) { try { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); } catch {} }
    // Handles of every visible standard DIALOG (#32770) on screen, any size. The caller closes the ones that appeared
    // AFTER launching the shortcut - so a modal licence/error dialog is dismissed BEFORE we force-kill (which is what
    // prevents the un-removable ghost), even when the dialog is owned by a helper process and not the app itself.
    public static List<long> Dialogs() {
        var r = new List<long>();
        EnumWindows((h,l)=>{ try { if (!IsWindowVisible(h)) return true;
            var cn = new StringBuilder(40); GetClassName(h, cn, 40); if (cn.ToString() == "#32770") r.Add((long)h);
        } catch {} return true; }, IntPtr.Zero);
        return r;
    }
    // The hidden-icons OVERFLOW flyout window (Win11 "TopLevelWindowForOverflowXamlIsland" / Win10 "NotifyIconOverflowWindow").
    // Returns its hwnd once opened, so we can screenshot the actual tray-icon panel (the icons live INSIDE it, not on the bar).
    public static IntPtr FindOverflowWindow() {
        IntPtr ov = IntPtr.Zero, isl = IntPtr.Zero;
        EnumWindows((h,l)=>{ try {
            if (!IsWindowVisible(h)) return true;
            var cn = new StringBuilder(160); GetClassName(h, cn, 160); string c = cn.ToString().ToLower();
            bool isOv = c.Contains("overflow"); bool isIsl = c.Contains("xamlisland") || c.Contains("islandwindow");
            if (isOv || isIsl) { RECT r; if (GetWindowRect(h, out r)) { int w=r.Right-r.Left, ht=r.Bottom-r.Top;
                if (w>20 && ht>20 && r.Left>-30000) { if (isOv && ov==IntPtr.Zero) ov=h; else if (isIsl && isl==IntPtr.Zero) isl=h; } } }
        } catch {} return true; }, IntPtr.Zero);
        return ov != IntPtr.Zero ? ov : isl;
    }
    // Force a window to the foreground + top, defeating Windows' foreground-stealing block (AttachThreadInput), so the
    // app - not the tool sitting behind it - is what gets captured in its rectangle. No reliance on minimizing the tool.
    public static void ForceForeground(IntPtr h) {
        try {
            if (IsIconic(h)) { ShowWindow(h, 9); } else { ShowWindow(h, 5); }   // SW_RESTORE / SW_SHOW
            IntPtr fg = GetForegroundWindow();
            uint pid; uint fgt = GetWindowThreadProcessId(fg, out pid);
            uint me = GetCurrentThreadId();
            AttachThreadInput(fgt, me, true);
            SetWindowPos(h, new IntPtr(-1), 0,0,0,0, 0x0013);   // HWND_TOPMOST, NOMOVE|NOSIZE|NOACTIVATE off
            SetWindowPos(h, new IntPtr(-2), 0,0,0,0, 0x0013);   // HWND_NOTOPMOST (so it doesn't stay always-on-top)
            BringWindowToTop(h);
            SetForegroundWindow(h);
            AttachThreadInput(fgt, me, false);
        } catch {}
    }
    // Enumerate VISIBLE, titled, non-tiny, non-tool TOP-LEVEL windows as "hwnd|pid|w|h|title" - so we find the app's
    // real window no matter WHICH process owns it (a Java/Electron/launcher app's window often belongs to a child
    // process with a different name, which is why matching by process name missed it).
    // DIAGNOSTIC: every visible, non-tiny top-level window with its props + filter reasons - logged on a miss so we
    // can SEE why a window (e.g. MASTA's titleless / topmost dialog) wasn't picked.
    public static List<string> GetAllWindowsDebug() {
        var list = new List<string>();
        EnumWindows((h, l) => { try {
            bool vis = IsWindowVisible(h); bool ico = IsIconic(h);
            RECT r; GetWindowRect(h, out r);
            int w = r.Right - r.Left, ht = r.Bottom - r.Top;
            if (!vis || ico || w < 60 || ht < 40) return true;
            int ex = GetWindowLong(h, -20); bool tool = (ex & 0x00000080) != 0;
            uint pid; GetWindowThreadProcessId(h, out pid);
            var sb = new StringBuilder(200); GetWindowText(h, sb, 200);
            list.Add(w + "x" + ht + " pid=" + pid + " topmost=" + ((ex & 0x00000008) != 0) + " tool=" + tool + " rect=" + r.Left + "," + r.Top + " '" + sb.ToString() + "'");
        } catch {} return true; }, IntPtr.Zero);
        return list;
    }
    public static List<string> GetAppWindows() {
        var list = new List<string>();
        EnumWindows((h, l) => {
            try {
                if (!IsWindowVisible(h) || IsIconic(h)) return true;
                RECT r; if (!GetWindowRect(h, out r)) return true;
                int w = r.Right - r.Left, ht = r.Bottom - r.Top;
                if (w < 160 || ht < 110) return true;
                if (r.Left <= -30000 || r.Top <= -30000) return true;   // off-screen / hidden (e.g. Citrix at -32768)
                // Do NOT require a title and do NOT exclude WS_EX_TOOLWINDOW - real app DIALOGS often have no title and
                // some set WS_EX_TOOLWINDOW (MASTA's licence-manager "No Settings Found" dialog is exactly this, which is
                // why it was missed). Instead exclude the actual desktop / taskbar / system shell windows by CLASS.
                var cn = new StringBuilder(96); GetClassName(h, cn, 96); string cls = cn.ToString();
                if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd" ||
                    cls == "NotifyIconOverflowWindow" || cls == "TaskListThumbnailWnd" || cls == "ForegroundStaging") return true;
                uint pid; GetWindowThreadProcessId(h, out pid);
                int style = GetWindowLong(h, -16);   // GWL_STYLE - lets the caller tell a real app window (WS_CAPTION) from a borderless splash
                var sb = new StringBuilder(260); GetWindowText(h, sb, 260);
                string title = sb.ToString(); if (title.Length == 0) title = "(no title)";
                list.Add(((long)h) + "|" + pid + "|" + w + "|" + ht + "|" + style + "|" + title);
            } catch {}
            return true;
        }, IntPtr.Zero);
        return list;
    }
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
    }
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
}

# Save a captured bitmap with a CAPTION strip along the bottom (shortcut name + target + time) so each PNG is
# self-identifying - "which screenshot is which shortcut" is answered on the image itself.
function Save-CaptionedPng {
    param([System.Drawing.Bitmap]$Bmp, [string]$Caption, [string]$SubCaption, [string]$Path)
    $barH = 46
    $out = New-Object System.Drawing.Bitmap($Bmp.Width, ($Bmp.Height + $barH))
    $g = [System.Drawing.Graphics]::FromImage($out)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(24,26,31))
        $g.DrawImage($Bmp, 0, 0, $Bmp.Width, $Bmp.Height)
        $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(16,32,43))), 0, $Bmp.Height, $out.Width, $barH)
        $f1 = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        $f2 = New-Object System.Drawing.Font('Consolas', 9)
        $g.DrawString($Caption,    $f1, [System.Drawing.Brushes]::White,    8, ($Bmp.Height + 4))
        $g.DrawString($SubCaption, $f2, [System.Drawing.Brushes]::LightGray, 9, ($Bmp.Height + 26))
        $out.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $g.Dispose(); $out.Dispose() }
}

# Write an index.html contact sheet so all shortcut screenshots are visible at a glance with their names + status.
function Write-ScreenshotIndex {
    param([object[]]$Results, [string]$OutDir, [string]$Title)
    $esc = { param($t) "$t" -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' }
    $rows = foreach ($r in @($Results)) {
        $imgs = @($r.Pngs | Where-Object { $_ -and (Test-Path $_) })
        if (-not $imgs.Count -and $r.Png -and (Test-Path $r.Png)) { $imgs = @($r.Png) }
        $img = if ($imgs.Count) {
            ($imgs | ForEach-Object { "<div style='display:inline-block;margin:4px;text-align:center'><img src='$([IO.Path]::GetFileName($_))' style='max-width:420px;border:1px solid #2E4760'><br><small style='color:#888'>$(& $esc ([IO.Path]::GetFileNameWithoutExtension($_)))</small></div>" }) -join ''
        } else { "<i>(no image)</i>" }
        # Colour by the per-shortcut Status so the engineer scans outcomes at a glance: ok=green, attention=amber,
        # fail=red, info=grey. Falls back to Ok/Note for older result objects without Status.
        $col = switch ("$($r.Status)") { 'ok' {'#6A9955'} 'attention' {'#E0BE7C'} 'fail' {'#E06C75'} 'info' {'#8A94A6'} default { if ($r.Ok) {'#6A9955'} else {'#E0BE7C'} } }
        $txt = if ($r.Outcome) { "$($r.Outcome)" } elseif ($r.Ok) { "OK ($($imgs.Count) image$(if($imgs.Count -ne 1){'s'}))" } else { "$($r.Note)" }
        $st  = "<span style='color:$col'>$(& $esc $txt)</span>$(if($imgs.Count){" <small style='color:#888'>($($imgs.Count) image$(if($imgs.Count -ne 1){'s'}))</small>"})"
        "<tr><td valign='top'><b>$(& $esc "$($r.Name)")</b><br><code>$(& $esc "$($r.Target)")</code><br>$st</td><td>$img</td></tr>"
    }
    $html = "<html><head><meta charset='utf-8'><title>$(& $esc $Title)</title></head><body style='background:#181A1F;color:#E7E9ED;font-family:Segoe UI'><h2>$(& $esc $Title)</h2><p>$(@($Results).Count) shortcut(s) - $((Get-Date).ToString('yyyy-MM-dd HH:mm'))</p><table cellpadding='8' style='border-collapse:collapse'>$(($rows) -join '')</table></body></html>"
    $idx = Join-Path $OutDir 'index.html'
    [IO.File]::WriteAllText($idx, $html)
    return $idx
}

# Launch each shortcut on a CLEAN desktop and screenshot the running app, then close it; write an index.html.
# SIMPLE flow, like a normal user double-clicking the shortcut: MINIMIZE EVERYTHING, launch the target (or the .lnk),
# WAIT for its window to come up, take a FIRST full-screen shot (no taskbar), wait 15s, and only keep a SECOND shot if
# the screen actually CHANGED, then close it.
# If NO window appears we DON'T blindly screenshot the tray - we VERIFY: compare the tray icons before vs after launch.
#   - a NEW tray icon appeared  -> the app really is a tray app: open the hidden-icons flyout + screenshot it (Ok).
#   - no new icon, process alive -> it runs in the background with no UI (a service-style app): reported, no shot.
#   - no new icon, process gone  -> it launched then exited (a stub/handoff or a failed launch): reported for a quick
#                                   manual check. So an engineer only ever looks at that last, rare case by hand.
# Returns @(@{ Name; Target; Png; Pngs; Ok; Note }). $OnLog is optional for progress.
function Invoke-ShortcutScreenshots {
    param([object[]]$Shortcuts, [Parameter(Mandatory)][string]$OutDir, [scriptblock]$OnLog,
          [int]$TimeoutSec = 45, [int]$SecondShotSec = 15, [string]$Title = 'Shortcut screenshots')   # wait up to TimeoutSec for ITS process window, shot 1, +SecondShotSec, shot 2; no window -> verified tray / background
    if (-not (Test-Path $OutDir)) { New-Item $OutDir -ItemType Directory -Force | Out-Null }
    $log = { param($m) try { if ($OnLog) { & $OnLog $m } } catch {}; if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $m } }
    Initialize-ScreenCapture
    # Shell.Application drives "minimize everything" (show desktop) so each capture is a CLEAN shot of ONLY the
    # launched app - nothing else on screen, incl. the tool itself. The user's windows are restored at the very end.
    $shell = $null; try { $shell = New-Object -ComObject Shell.Application } catch {}
    $results = New-Object System.Collections.Generic.List[object]
    # --- TRAY VERIFICATION HELPERS (shared by every shortcut) -------------------------------------------------------
    # Open the taskbar "show hidden icons" tray flyout (the ^ arrow) via UI Automation Invoke (no mouse), falling back
    # to a click on the button's centre. Returns $true if a tray button was triggered.
    $openTray = {
        try { Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue; Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue } catch {}
        try {
            $tray = [PBScreen]::FindWindow('Shell_TrayWnd', $null)
            if ($tray -eq [IntPtr]::Zero) { return $false }
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($tray)
            if (-not $root) { return $false }
            $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
            foreach ($b in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
                $nm = ''; $aid = ''
                try { $nm = "$($b.Current.Name)" } catch {}
                try { $aid = "$($b.Current.AutomationId)" } catch {}
                if (($nm -match '(?i)hidden|overflow|ausgeblendet|einblenden|infobereich|symbole') -or ($aid -match '(?i)overflow|systemtray|chevron')) {
                    try { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true } catch {}
                    try { $rc = $b.Current.BoundingRectangle; [PBScreen]::ClickAt([int]($rc.X + $rc.Width / 2), [int]($rc.Y + $rc.Height / 2)); return $true } catch {}
                }
            }
        } catch {}
        return $false
    }
    # COUNT the notification-area icons (visible tray + the overflow flyout if it is open). We compare the COUNT before
    # vs after launch - NOT the names - because real tray names are volatile on this box ("Task Manager CPU 27%",
    # "Unplugged: 42%", "File Explorer - 4 running windows"): a name diff would treat every % tick as a "new icon". A
    # count is immune to that - it only goes up when a genuinely new icon appears. Taskbar running-app buttons and the
    # fixed shell buttons (Start/Search/Widgets/the chevron) are excluded so they don't inflate the count.
    $countTray = {
        try { Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue; Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue } catch {}
        $skip  = '(?i)^(start|search|task ?view|aufgabenansicht|widgets|copilot|chat|meet now|people|show desktop|desktop anzeigen|show hidden icons|ausgeblendete symbole|running applications|taskbar)$'
        $tbApp = '(?i)running window|wird ausgef|\bl.uft\b|angeheftet|\bpinned\b'   # taskbar app button, not a tray icon
        $countIn = {
            param($h)
            if ($h -eq [IntPtr]::Zero) { return 0 }
            $c = 0
            try {
                $r = [System.Windows.Automation.AutomationElement]::FromHandle($h); if (-not $r) { return 0 }
                $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
                foreach ($b in $r.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
                    $nm = ''; try { $nm = "$($b.Current.Name)".Trim() } catch {}
                    if (-not $nm) { continue }
                    if ($nm -match $skip)  { continue }
                    if ($nm -match $tbApp) { continue }
                    $c++
                }
            } catch {}
            return $c
        }
        return ((& $countIn ([PBScreen]::FindOverflowWindow())) + (& $countIn ([PBScreen]::FindWindow('Shell_TrayWnd', $null))))
    }
    # One-time BASELINE count of tray icons before any app launched (flyout opened so hidden icons are counted too).
    $trayBaseCount = 0
    try { if (& $openTray) { Start-Sleep -Milliseconds 800; $trayBaseCount = & $countTray; [PBScreen]::PressEsc(); Start-Sleep -Milliseconds 300 } else { $trayBaseCount = & $countTray } } catch {}
    $n = 0
    try {
      foreach ($s in @($Shortcuts)) {
        $n++; $note = ''; $png = ''; $outcome = ''; $status = 'ok'; $pk2 = $null; $ourPids = @{}
        # Classify what a window TITLE means, so the report flags a shortcut that opened an ERROR/prompt vs a clean app
        # window - the packaging engineer scans the contact sheet and instantly sees which ones need a look. (EN + DE.)
        $errRe    = '(?i)error|fehler|exception|failed|\bfail\b|cannot|can.t|could ?n.t|not found|nicht gefunden|unable|missing|fehlt|denied|verweigert|invalid|ung.ltig|crash|has stopped|not responding|reagiert nicht|no settings'
        $promptRe = '(?i)licen[cs]e|lizenz|activation|aktivierung|\btrial\b|expired|abgelaufen|sign ?in|log ?in|anmelden|welcome|willkommen|first ?run|getting started|register|registr|update available'
        if ((Get-Command Test-IsSecurityProduct -ErrorAction SilentlyContinue) -and (Test-IsSecurityProduct "$($s.Name) $($s.Target)")) {
            & $log "  [shot] SKIP security/EDR app (won't relaunch): $($s.Name)"
            $results.Add([pscustomobject]@{ Name=$s.Name; Target=$s.Target; Png=''; Pngs=@(); Ok=$false; Note='skipped (security product)'; Outcome='skipped - security/EDR product (not relaunched)'; Status='info' }); continue
        }
        # MINIMIZE EVERYTHING before launching, so the app comes up on an empty desktop and the shot is unambiguous.
        if ($shell) { try { $shell.MinimizeAll(); Start-Sleep -Milliseconds 600 } catch {} }
        # Snapshot the top-level windows that ALREADY exist, so after launch we can tell which window is NEW (the app's)
        # - independent of which process owns it. Key by hwnd.
        $beforeWins = @{}; try { foreach ($wl in [PBScreen]::GetAppWindows()) { $beforeWins[$wl.Split('|',2)[0]] = $true } } catch {}
        # Snapshot the PIDs running BEFORE launch. After launch, the app's processes (the target + any children it spawns,
        # e.g. javaw.exe for MASTA) are the NEW pids - our "Task Manager" view of what THIS shortcut started. It lets us
        # (a) wait until the app's OWN window shows, (b) never grab another shortcut's window, (c) close it cleanly.
        $beforePids = @{}; try { foreach ($pp in (Get-Process -ErrorAction SilentlyContinue)) { $beforePids[$pp.Id] = $true } } catch {}
        & $log "  [shot] ($n/$(@($Shortcuts).Count)) launching $($s.Name) (wait for ITS process window up to ${TimeoutSec}s, shot 1, +${SecondShotSec}s shot 2)..."
        # Launch the SHORTCUT the way a user double-clicks it (Start-Process on the .lnk via the shell) - that honours the
        # target, arguments, working dir, "run as", and file/Store/appref associations, so odd shortcuts still start.
        # Fall back to the target exe (+ args + workdir) if there is no usable .lnk. Returns @{ Proc; Err }.
        $launch = {
            $p = $null; $err = ''
            if ("$($s.Lnk)".Trim() -and (Test-Path -LiteralPath "$($s.Lnk)")) {
                try { $p = Start-Process -FilePath $s.Lnk -PassThru -ErrorAction Stop } catch { $err = "$($_.Exception.Message)" }
            }
            if ((-not $p) -and "$($s.Target)".Trim()) {
                try {
                    $sp = @{ FilePath = $s.Target; PassThru = $true; ErrorAction = 'Stop' }
                    if ("$($s.Args)".Trim())    { $sp['ArgumentList'] = "$($s.Args)" }
                    if ("$($s.WorkDir)".Trim() -and (Test-Path -LiteralPath "$($s.WorkDir)")) { $sp['WorkingDirectory'] = "$($s.WorkDir)" }
                    $p = Start-Process @sp
                } catch { $err = "$($_.Exception.Message)" }
            }
            return @{ Proc = $p; Err = $err }
        }
        $launchAt = Get-Date
        $lr = & $launch; $proc = $lr.Proc
        if ((-not $proc) -and $lr.Err) { $note = "launch failed: $($lr.Err)" }
        # Find THIS shortcut's window: the largest window that (a) appeared AFTER we launched and (b) is OWNED BY one of
        # the processes this shortcut started ($pids - the new-pid set). EnumWindows is process-agnostic so a window under
        # a CHILD process (javaw.exe for MASTA, an Electron/host exe) is still found - we just require its pid to be ours.
        # Tying the window to OUR process is what stops a different (slow) shortcut's late window being captured here.
        $pickOur = {
            param($pids)
            $fg = [IntPtr]::Zero; try { $fg = [PBScreen]::GetForegroundWindow() } catch {}
            $best=[IntPtr]::Zero; $bestArea=0; $bestPid=0; $bestTitle=''; $cnt=0
            $fgH=[IntPtr]::Zero; $fgPidV=0; $fgTitle=''
            try {
                foreach ($wl in [PBScreen]::GetAppWindows()) {
                    $parts = $wl.Split('|', 6); if ($parts.Count -lt 6) { continue }
                    $hl = 0; [long]::TryParse($parts[0], [ref]$hl) | Out-Null; if ($hl -eq 0) { continue }
                    $wpid = 0; [int]::TryParse($parts[1], [ref]$wpid) | Out-Null
                    if ($wpid -eq $PID) { continue }                          # never our own tool window
                    if (-not $pids.ContainsKey($wpid)) { continue }           # ONLY a window owned by THIS shortcut's process
                    if ($beforeWins.ContainsKey($parts[0])) { continue }      # and only one that appeared AFTER we launched
                    $aw=0; $ah=0; [int]::TryParse($parts[2], [ref]$aw) | Out-Null; [int]::TryParse($parts[3], [ref]$ah) | Out-Null; $area = $aw * $ah
                    $cnt++
                    if ($area -gt $bestArea) { $best=[IntPtr]$hl; $bestArea=$area; $bestPid=$wpid; $bestTitle=$parts[5] }
                    if (([IntPtr]$hl -eq $fg)) { $fgH=[IntPtr]$hl; $fgPidV=$wpid; $fgTitle=$parts[5] }   # the active dialog, if ours
                }
            } catch {}
            # Prefer the FOREGROUND window if it is one of ours (that is the active dialog, e.g. MASTA's licence prompt,
            # which sits OVER the bigger splash) - else fall back to the largest. The shot is full-screen either way; this
            # just makes us foreground + report the meaningful window, not the splash behind it.
            if ($fgH -ne [IntPtr]::Zero) { return @{ H=$fgH; Pid=[int]$fgPidV; Title=$fgTitle; Count=$cnt } }
            return @{ H=$best; Pid=[int]$bestPid; Title=$bestTitle; Count=$cnt }
        }
        $safe = ($s.Name -replace '[^\w\.\-]', '_'); if (-not $safe) { $safe = "shortcut$n" }
        # FULL-SCREEN capture (no per-window cropping - simple + reliable). WorkingArea EXCLUDES the taskbar (the clean
        # "without taskbar" shot for a normal app); Bounds INCLUDES it (used for the tray case so the icon is in frame).
        $grabScreen = {
            param([bool]$withTaskbar)
            try {
                $area = if ($withTaskbar) { [System.Windows.Forms.Screen]::PrimaryScreen.Bounds } else { [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
                $bmp = New-Object System.Drawing.Bitmap($area.Width, $area.Height)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.CopyFromScreen($area.X, $area.Y, 0, 0, (New-Object System.Drawing.Size($area.Width, $area.Height))); $g.Dispose()
                return $bmp
            } catch { return $null }
        }
        # Zoom the bottom-right notification area so a TRAY icon is actually recognisable in the saved image.
        $grabTrayZoom = {
            try {
                $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                $tw = 520; $th = 90; $tx = $b.Right - $tw; $ty = $b.Bottom - $th
                $src = New-Object System.Drawing.Bitmap($tw, $th); $g = [System.Drawing.Graphics]::FromImage($src)
                $g.CopyFromScreen($tx, $ty, 0, 0, (New-Object System.Drawing.Size($tw, $th))); $g.Dispose()
                $zw = [int]($tw * 2.4); $zh = [int]($th * 2.4)
                $z = New-Object System.Drawing.Bitmap($zw, $zh); $g2 = [System.Drawing.Graphics]::FromImage($z)
                $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $g2.DrawImage($src, 0, 0, $zw, $zh); $g2.Dispose(); $src.Dispose(); return $z
            } catch { return $null }
        }
        # Caption + save a bitmap under NN_<name>_<suffix>.png. Disposes the bitmap. Returns the path (or $null).
        $saveShot = {
            param($bmp, $suffix)
            if (-not $bmp) { return $null }
            $p = Join-Path $OutDir ("{0:D2}_{1}_{2}.png" -f $n, $safe, $suffix)
            try { Save-CaptionedPng -Bmp $bmp -Caption "$n. $($s.Name)  ($suffix)" -SubCaption "$($s.Target)   $(Get-Date -Format 'HH:mm:ss')$(if($note){"   [$note]"})" -Path $p } catch {}
            $bmp.Dispose(); return $p
        }
        # Tiny 24x24 signature + a "did it change" test - ONLY to skip a duplicate second shot when the screen is identical
        # (the app launched fully in one go). This is a simple sameness check, NOT loading detection.
        $sig = {
            param($bmp)
            if (-not $bmp) { return $null }
            try {
                $t = New-Object System.Drawing.Bitmap(24, 24); $g = [System.Drawing.Graphics]::FromImage($t)
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
                $g.DrawImage($bmp, 0, 0, 24, 24); $g.Dispose()
                $a = New-Object 'int[]' 576; $i = 0
                for ($y = 0; $y -lt 24; $y++) { for ($x = 0; $x -lt 24; $x++) { $px = $t.GetPixel($x, $y); $a[$i] = [int](([int]$px.R + [int]$px.G + [int]$px.B) / 3); $i++ } }
                $t.Dispose(); return $a
            } catch { return $null }
        }
        $differ = {   # $true if the two signatures differ enough to be a real change (>12 of 576 cells)
            param($a, $b)
            if ((-not $a) -or (-not $b)) { return $true }
            $d = 0; for ($i = 0; $i -lt $a.Length; $i++) { if ([Math]::Abs($a[$i] - $b[$i]) -gt 28) { $d++ } }
            return ($d -gt 12)
        }
        # Capture a SINGLE window's rectangle (used for the tray-overflow flyout), optionally scaled up for readability.
        $grabWindow = {
            param($h, $scale)
            try {
                $r = New-Object PBScreen+RECT
                if (-not [PBScreen]::GetWindowRect($h, [ref]$r)) { return $null }
                $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
                if (($w -le 4) -or ($ht -le 4)) { return $null }
                $src = New-Object System.Drawing.Bitmap($w, $ht); $g = [System.Drawing.Graphics]::FromImage($src)
                $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $ht))); $g.Dispose()
                if ((-not $scale) -or ($scale -le 1)) { return $src }
                $zw = [int]($w * $scale); $zh = [int]($ht * $scale)
                $z = New-Object System.Drawing.Bitmap($zw, $zh); $g2 = [System.Drawing.Graphics]::FromImage($z)
                $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $g2.DrawImage($src, 0, 0, $zw, $zh); $g2.Dispose(); $src.Dispose(); return $z
            } catch { return $null }
        }
        $shotPaths = New-Object System.Collections.Generic.List[string]; $fgPid = 0
        try {
            # MONITOR like Task Manager: track the processes THIS shortcut started (new pids since launch, incl. children
            # such as javaw.exe), and WAIT for a window OWNED BY ONE OF THEM. We keep waiting while the app is still
            # starting (any of its processes is alive) up to TimeoutSec - that is "wait till it shows up". We do NOT
            # relaunch (that just made duplicate, mixed-up windows). Nothing showing + nothing of ours alive = stop early.
            $ourPids = @{}
            $hwnd = [IntPtr]::Zero; $picked = $null
            $deadline = (Get-Date).AddSeconds($TimeoutSec); $graceExit = (Get-Date).AddSeconds(6)
            while ($true) {
                try { foreach ($pp in (Get-Process -ErrorAction SilentlyContinue)) { if ((-not $beforePids.ContainsKey($pp.Id)) -and ($pp.Id -ne $PID)) { $ourPids[$pp.Id] = $true } } } catch {}
                if ($proc -and $proc.Id) { $ourPids[$proc.Id] = $true }
                $picked = & $pickOur $ourPids
                if ($picked.H -ne [IntPtr]::Zero) { $hwnd = $picked.H; $fgPid = [int]$picked.Pid; break }
                $aliveOur = 0; foreach ($k in @($ourPids.Keys)) { try { if (Get-Process -Id $k -ErrorAction SilentlyContinue) { $aliveOur++ } } catch {} }
                if ((Get-Date) -ge $deadline) { break }
                if (($aliveOur -eq 0) -and ((Get-Date) -ge $graceExit)) { break }
                Start-Sleep -Milliseconds 1000
            }
            if ($hwnd -ne [IntPtr]::Zero) {
                # A window came up -> front it, let it draw, take SHOT 1. Wait SecondShotSec, then look again: only keep a
                # SECOND shot if the screen actually CHANGED (a dialog popped / it finished loading). If it's identical
                # (launched fully in one go) one shot is enough - no duplicate. (re-front first in case a dialog is on top.)
                try { [PBScreen]::ForceForeground($hwnd) } catch {}; Start-Sleep -Milliseconds 1200
                & $log "  [shot] $($s.Name): window up ('$($picked.Title)') - taking the first screenshot."
                $b1 = & $grabScreen $false; $sig1 = & $sig $b1
                $p1 = & $saveShot $b1 'shot1'; if ($p1) { $shotPaths.Add($p1) }
                & $log "  [shot] $($s.Name): waiting ${SecondShotSec}s, then checking whether the screen changed..."
                Start-Sleep -Seconds $SecondShotSec
                try { $pk2 = & $pickOur $ourPids; if ($pk2.H -ne [IntPtr]::Zero) { [PBScreen]::ForceForeground($pk2.H); $fgPid = [int]$pk2.Pid } } catch {}
                Start-Sleep -Milliseconds 500
                $b2 = & $grabScreen $false
                $changed = (& $differ $sig1 (& $sig $b2))
                if ($changed) {
                    $p2 = & $saveShot $b2 'shot2'; if ($p2) { $shotPaths.Add($p2) }
                    & $log "  [shot] $($s.Name): screen changed -> kept a second screenshot."
                } else {
                    if ($b2) { $b2.Dispose() }
                    & $log "  [shot] $($s.Name): screen unchanged after ${SecondShotSec}s -> one screenshot is enough."
                }
                # Classify the (latest) window so the report says WHAT opened - a clean app window vs an error/prompt.
                $ttl = if ($pk2 -and $pk2.Title) { "$($pk2.Title)" } else { "$($picked.Title)" }
                if     ($ttl -match $errRe)    { $outcome = "opened an ERROR / problem window: '$ttl'"; $status = 'attention' }
                elseif ($ttl -match $promptRe) { $outcome = "opened a prompt / dialog (not the main UI): '$ttl'"; $status = 'attention' }
                else                           { $outcome = "app window opened: '$ttl'"; $status = 'ok' }
                if ($changed) { $outcome += ' (+ a second view after it settled)' }
                $note = $outcome
            } else {
                # NO window appeared. Don't blind-capture the tray - work out WHY, like an engineer would:
                #   1) did the app ADD ITS OWN tray icon? (before/after diff) -> real tray app: capture the flyout.
                #   2) else is the process still alive?    -> background/service-style app, no UI (nothing to shoot).
                #   3) else                                -> it launched then exited (stub/handoff or a failed start).
                if ($note -match '(?i)launch failed') {
                    $outcome = "did not start: $note"; $status = 'fail'
                    & $log "  [shot] $($s.Name): $outcome"
                } else {
                    $alive = $false; foreach ($k in @($ourPids.Keys)) { try { if (Get-Process -Id $k -ErrorAction SilentlyContinue) { $alive = $true; break } } catch {} }
                    & $log "  [shot] $($s.Name): no window appeared - checking whether it added a tray icon..."
                    Start-Sleep -Seconds 4                                   # give it a moment to place a tray icon
                    $opened = & $openTray; Start-Sleep -Milliseconds 800     # open the flyout so HIDDEN icons are counted too
                    $nowCount = & $countTray
                    & $log "  [shot] $($s.Name): tray icon count $trayBaseCount -> $nowCount."
                    if ($nowCount -gt $trayBaseCount) {
                        # CONFIRMED: a NEW tray icon really appeared after launching -> screenshot the flyout it lives in.
                        $outcome = 'tray app - it added a tray icon (no main window)'; $status = 'ok'; $note = $outcome
                        & $log "  [shot] $($s.Name): a new tray icon appeared - capturing the hidden-icons flyout."
                        $fly = [IntPtr]::Zero; try { $fly = [PBScreen]::FindOverflowWindow() } catch {}
                        if ($fly -ne [IntPtr]::Zero) { $t1 = & $saveShot (& $grabWindow $fly 2.2) 'tray_icon'; if ($t1) { $shotPaths.Add($t1) } }
                        else                         { $t1 = & $saveShot (& $grabTrayZoom) 'tray_icon'; if ($t1) { $shotPaths.Add($t1) } }
                    } elseif ($alive) {
                        $outcome = 'runs in the background - no window and no new tray icon (service-style app; nothing to screenshot)'; $status = 'info'; $note = $outcome
                        & $log "  [shot] $($s.Name): $outcome"
                    } else {
                        $outcome = 'launched then exited with no window or tray icon (a launcher/stub handoff, or it failed to start) - worth a quick manual check'; $status = 'attention'; $note = $outcome
                        & $log "  [shot] $($s.Name): $outcome"
                    }
                    try { [PBScreen]::PressEsc() } catch {}                  # close the flyout we opened
                }
            }
        } catch { $note = "capture failed: $($_.Exception.Message)"; $outcome = $note; $status = 'fail'; & $log "  [shot] $($s.Name): $note" }
        if (-not $shotPaths.Count -and -not $note) { $note = 'no screenshot captured'; $outcome = $note }
        if (-not $outcome) { $outcome = $note }
        $png = if ($shotPaths.Count) { $shotPaths[0] } else { '' }
        # Record the TITLES of this shortcut's windows NOW (app still alive) - so if a window is left behind by an
        # UNTRACKED process and can't be closed by pid, we can still close it by title afterwards (your suggestion).
        $appTitles = @{}
        try { foreach ($wl in [PBScreen]::GetAppWindows()) { $tp = $wl.Split('|', 6); if ($tp.Count -ge 6) { $tpid = 0; [int]::TryParse($tp[1], [ref]$tpid) | Out-Null; if ($ourPids.ContainsKey($tpid) -and $tp[5] -and ($tp[5] -ne '(no title)')) { $appTitles["$($tp[5])"] = $true } } } } catch {}
        # CLOSE only THIS shortcut's OWN process tree: the launched process + the captured window's process + THEIR
        # CHILDREN (resolved from real parent/child links via Win32_Process - so a child the app spawned after launch is
        # included). We do NOT kill by name and do NOT kill "any new pid", so:
        #   - a Windows SERVICE that merely shares the app's name is NEVER touched (services are excluded outright), and
        #   - an unrelated process that happened to start is never touched.
        # Best-effort: every step is wrapped - any error on one process is logged and skipped, never aborts the run.
        $killSet = @{}
        try {
            $allProc = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId, ParentProcessId, Name)
            $svcPids = @{}; foreach ($sv in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) { if ($sv.ProcessId) { $svcPids["$($sv.ProcessId)"] = $true } }
            $roots = New-Object System.Collections.Generic.List[int]
            try { if ($proc -and $proc.Id) { $roots.Add([int]$proc.Id) } } catch {}
            if ($fgPid) { $roots.Add([int]$fgPid) }
            $queue = New-Object System.Collections.Generic.Queue[int]
            foreach ($r in $roots) { if (-not $killSet.ContainsKey("$r")) { $killSet["$r"] = $true; $queue.Enqueue($r) } }
            while ($queue.Count) {
                $cur = $queue.Dequeue()
                foreach ($pr in $allProc) { if (([int]$pr.ParentProcessId -eq $cur) -and (-not $killSet.ContainsKey("$([int]$pr.ProcessId)"))) { $killSet["$([int]$pr.ProcessId)"] = $true; $queue.Enqueue([int]$pr.ProcessId) } }
            }
            # never touch: SERVICES (incl. same-named), our own tool, or core shell processes
            $core = '(?i)^(services|svchost|lsass|csrss|wininit|smss|winlogon|dwm|explorer|fontdrvhost|powershell|pwsh|packagebuilder)$'
            foreach ($k in @($killSet.Keys)) {
                if ($svcPids.ContainsKey($k) -or ($k -eq "$PID")) { $killSet.Remove($k); continue }
                $pr = $allProc | Where-Object { "$($_.ProcessId)" -eq $k } | Select-Object -First 1
                if ($pr -and (("$($pr.Name)" -replace '\.exe$','') -match $core)) { $killSet.Remove($k) }
            }
        } catch { & $log "  [shot] $($s.Name): close - could not map the process tree (skipping kill): $($_.Exception.Message)" }
        # GRACEFUL drain first: WM_CLOSE every window the app's processes own (dialogs included), in a short loop. This
        # dismisses modal dialogs (e.g. MASTA's "licence not found" / "No Settings" prompts) one after another while the
        # app is still alive, so an app that can exit does, and - crucially - there is NO modal dialog up when we then
        # force-kill. Killing a process that is showing a modal dialog leaves an un-removable Windows "ghost" window that
        # lingers on screen into the NEXT shortcut (the cause of the mixed-up captures); killing on a plain window does not.
        $pidCsv = (@($killSet.Keys) -join ',')
        for ($gc = 0; $gc -lt 8; $gc++) {
            # (a) WM_CLOSE every window owned by this shortcut's processes, and (b) WM_CLOSE any standard DIALOG (#32770)
            # that appeared AFTER we launched - regardless of which process owns it - so a modal licence/error prompt is
            # dismissed before the kill. We only force-kill once NO such dialog is left up (kill-on-dialog = ghost).
            if ($pidCsv) { try { [PBScreen]::CloseWindowsForPids($pidCsv) | Out-Null } catch { & $log "  [shot] $($s.Name): close (WM_CLOSE) error: $($_.Exception.Message)" } }
            $newDlg = 0
            try { foreach ($dh in [PBScreen]::Dialogs()) { if (-not $beforeWins.ContainsKey("$dh")) { $newDlg++; [PBScreen]::CloseWindow([IntPtr][long]$dh) } } } catch {}
            Start-Sleep -Milliseconds 900
            $anyAlive = $false; foreach ($k in @($killSet.Keys)) { try { if (Get-Process -Id ([int]$k) -ErrorAction SilentlyContinue) { $anyAlive = $true; break } } catch {} }
            # done once the app exited OR (it's settled with no leftover dialog) after at least 2 rounds
            if (-not $anyAlive) { break }
            if (($newDlg -eq 0) -and ($gc -ge 2)) { break }
        }
        # final tight sweep: dismiss any dialog that popped up in the last instant, then kill immediately (no gap for a
        # new modal dialog to appear) - this is what keeps the force-kill from landing on a dialog and leaving a ghost.
        try { foreach ($dh in [PBScreen]::Dialogs()) { if (-not $beforeWins.ContainsKey("$dh")) { [PBScreen]::CloseWindow([IntPtr][long]$dh) } } } catch {}
        Start-Sleep -Milliseconds 400
        # force-kill any survivors - PER PROCESS, errors logged + skipped. WM_CLOSE just dismissed any modal dialog, so
        # this kill lands on a plain window (or none) and does not create a ghost.
        foreach ($k in @($killSet.Keys)) {
            try { $pr = Get-Process -Id ([int]$k) -ErrorAction SilentlyContinue; if ($pr -and -not $pr.HasExited) { Stop-Process -Id ([int]$k) -Force -ErrorAction Stop } }
            catch { & $log "  [shot] $($s.Name): close (force) skipped pid ${k}: $($_.Exception.Message)" }
        }
        # TITLE fallback (your suggestion): a window left on screen by an UNTRACKED process (a helper/licensing UI that
        # isn't in our pid tree) won't have been closed above. Find any visible window whose TITLE matches one this
        # shortcut showed and close it - WM_CLOSE, and if a non-service live process owns it, end that too. Services and
        # dead "ghost" windows simply won't respond and are left as-is. Goal: a CLEAR screen before the next shortcut.
        if ($appTitles.Count) {
            Start-Sleep -Milliseconds 500
            try {
                foreach ($wl in [PBScreen]::GetAppWindows()) {
                    $tp = $wl.Split('|', 6); if ($tp.Count -lt 6) { continue }
                    if (-not $appTitles.ContainsKey("$($tp[5])")) { continue }
                    $hl = 0; [long]::TryParse($tp[0], [ref]$hl) | Out-Null; if ($hl -eq 0) { continue }
                    $wp = 0; [int]::TryParse($tp[1], [ref]$wp) | Out-Null; if ($wp -eq $PID) { continue }
                    try { [PBScreen]::CloseWindow([IntPtr]$hl) } catch {}
                    try { $pr = Get-Process -Id $wp -ErrorAction SilentlyContinue
                          if ($pr -and (-not $svcPids.ContainsKey("$wp")) -and ($pr.ProcessName -notmatch '(?i)^(services|svchost|lsass|csrss|wininit|smss|winlogon|dwm|explorer|fontdrvhost|powershell|pwsh|packagebuilder)$')) {
                              & $log "  [shot] $($s.Name): closing leftover window by title ('$($tp[5])', $($pr.ProcessName) pid $wp)."; Stop-Process -Id $wp -Force -ErrorAction SilentlyContinue } }
                    catch { & $log "  [shot] $($s.Name): title-close skipped '$($tp[5])': $($_.Exception.Message)" }
                }
            } catch {}
        }
        $results.Add([pscustomobject]@{ Name=$s.Name; Target=$s.Target; Png=$png; Pngs=@($shotPaths); Ok=([bool]$png -and (Test-Path $png)); Note=$note; Outcome=$outcome; Status=$status })
      }
    } finally {
        # Restore everything we minimized (incl. the tool window) so the user's desktop is left as it was.
        if ($shell) { try { $shell.UndoMinimizeALL() } catch {}; try { [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null } catch {} }
    }
    try { Write-ScreenshotIndex -Results $results.ToArray() -OutDir $OutDir -Title $Title | Out-Null } catch {}
    return $results.ToArray()
}

#region Remote shortcut screenshots (smoke-test on a TEST machine) --------------------------------------------------
# The tool can't screenshot another machine directly - so it generates a SELF-CONTAINED agent script (PBShots.ps1),
# copies it to the remote's C:\temp (c$\temp - NOT Windows\Temp, whose ACLs can demand explicit elevation), runs it
# via a scheduled task IN THE LOGGED-ON USER'S INTERACTIVE SESSION (works even when the RDP session is LOCKED -
# locked is still logged on), then pulls the report back and cleans up. Capture uses PrintWindow(PW_RENDERFULLCONTENT),
# which renders the window ITSELF - so it works on a locked/disconnected session where a screen-copy would grab the
# lock screen; CopyFromScreen remains the fallback for GPU-composited apps that PrintWindow renders black.
function New-PBShotsAgentScript {
    param([string]$PkgName, [string[]]$Tokens, [string[]]$RefNames, [string]$RemoteOut = 'C:\temp\PBShots\out')
    $tok = (@($Tokens   | Where-Object { "$_".Trim() } | ForEach-Object { "'" + ($_ -replace "'","''") + "'" }) -join ',')
    $ref = (@($RefNames | Where-Object { "$_".Trim() } | ForEach-Object { "'" + ($_ -replace "'","''") + "'" }) -join ',')
    if (-not $tok) { $tok = "''" }
    $tpl = @'
# PBShots agent - generated by Package Assistance. Runs ON the test machine, in the logged-on user's session.
$ErrorActionPreference = 'SilentlyContinue'
$out = '__PB_OUT__'; $tokens = @(__PB_TOKENS__); $refs = @(__PB_REFS__); $pkg = '__PB_PKG__'
New-Item $out -ItemType Directory -Force | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PBShotsNative {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
$exclude = '(?i)uninstall|unins|remove|update|upgrade|repair|readme|help|manual|documentation|website|homepage|release notes|support|licen[cs]e|eula'
# Discover the app's Start-Menu shortcuts: prefer the EXACT reference names captured at packaging time; else token match.
$ws = New-Object -ComObject WScript.Shell
$lnks = @()
foreach ($base in @([Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Programs'))) {
    if ($base -and (Test-Path $base)) { $lnks += @(Get-ChildItem -Path $base -Recurse -Filter *.lnk -File) }
}
$cand = @()
foreach ($l in $lnks) {
    if ($l.BaseName -match $exclude) { continue }
    $t = ''; try { $t = $ws.CreateShortcut($l.FullName).TargetPath } catch {}
    if (-not $t -or $t -notmatch '(?i)\.exe$' -or -not (Test-Path $t)) { continue }
    $byRef = ($refs.Count -and ($refs -contains $l.BaseName))
    $byTok = $false; foreach ($k in $tokens) { if ($k -and (($l.BaseName -match [regex]::Escape($k)) -or ($t -match [regex]::Escape($k)))) { $byTok = $true; break } }
    if ($byRef -or $byTok) { $cand += [pscustomobject]@{ Lnk=$l.FullName; Name=$l.BaseName; Target=$t; ByRef=$byRef } }
}
if (@($cand | Where-Object ByRef).Count) { $cand = @($cand | Where-Object ByRef) }   # exact reference wins over fuzzy tokens
$cand = @($cand | Sort-Object Name -Unique)
function Save-Shot([IntPtr]$h, [string]$png) {
    $r = New-Object PBShotsNative+RECT
    if (-not [PBShotsNative]::GetWindowRect($h, [ref]$r)) { return $false }
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    if ($w -le 20 -or $ht -le 20) { return $false }
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc(); [void][PBShotsNative]::PrintWindow($h, $dc, 2); $g.ReleaseHdc($dc); $g.Dispose()
    # black-frame check: PrintWindow can render GPU-composited apps black - fall back to a screen copy (needs unlocked).
    $dark = 0; $n = 0
    for ($x = 10; $x -lt $w; $x += [Math]::Max(1, [int]($w/12))) { for ($y = 10; $y -lt $ht; $y += [Math]::Max(1, [int]($ht/12))) {
        $p = $bmp.GetPixel($x, $y); $n++; if (($p.R + $p.G + $p.B) -lt 24) { $dark++ } } }
    if ($n -gt 0 -and ($dark / $n) -gt 0.97) {
        try {
            [void][PBShotsNative]::SetForegroundWindow($h); Start-Sleep -Milliseconds 600
            $g2 = [System.Drawing.Graphics]::FromImage($bmp)
            $g2.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $ht))); $g2.Dispose()
        } catch {}
    }
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); return $true
}
$results = @(); $i = 0
foreach ($c in $cand) {
    $i++
    $ok = $false; $note = ''
    $before = Get-Date
    try { Start-Process -FilePath $c.Lnk } catch { $note = "launch failed: $($_.Exception.Message)" }
    $proc = $null
    if (-not $note) {
        $deadline = (Get-Date).AddSeconds(45)
        while ((Get-Date) -lt $deadline -and -not $proc) {
            Start-Sleep -Seconds 2
            $proc = @(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.StartTime -gt $before -and $_.ProcessName -ne 'explorer' } | Sort-Object StartTime -Descending) | Select-Object -First 1
        }
        if ($proc) {
            Start-Sleep -Seconds 12                       # let splash -> main settle
            try { $proc.Refresh() } catch {}
            $h = $proc.MainWindowHandle
            if ($h -eq 0) { $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue; if ($proc) { $h = $proc.MainWindowHandle } }
            $png = Join-Path $out ("{0:D2}_{1}.png" -f $i, ($c.Name -replace '[\\/:*?"<>|]','_'))
            if ($h -ne 0 -and (Save-Shot $h $png)) { $ok = $true } else { $note = 'no capturable window' }
            try { [void]$proc.CloseMainWindow(); Start-Sleep -Seconds 3 } catch {}
            try { if (-not $proc.HasExited) { & taskkill /PID $proc.Id /T /F 2>$null | Out-Null } } catch {}
        } else { $note = 'no window appeared within 45s' }
    }
    $results += [pscustomobject]@{ Name = $c.Name; Ok = $ok; Note = $note }
}
# index.html + done flag (the tool polls for the flag, then pulls this folder back).
$rows = ($results | ForEach-Object {
    $img = Get-ChildItem $out -Filter ("*_" + ($_.Name -replace '[\\/:*?"<>|]','_') + ".png") | Select-Object -First 1
    "<div style='margin:14px 0'><h3 style='margin:4px 0;font-family:Segoe UI'>$($_.Name) $(if($_.Ok){'&#9989;'}else{'&#10060; ' + $_.Note})</h3>$(if($img){"<img src='$($img.Name)' style='max-width:96%;border:1px solid #888'/>"})</div>" }) -join "`r`n"
"<html><body style='background:#1b1d22;color:#eee'><h2 style='font-family:Segoe UI'>PBShots - $pkg on $env:COMPUTERNAME ($(Get-Date))</h2>$rows</body></html>" |
    Set-Content (Join-Path $out 'index.html') -Encoding UTF8
$results | ConvertTo-Json | Set-Content (Join-Path $out 'done.flag') -Encoding UTF8
'@
    return $tpl.Replace('__PB_OUT__', $RemoteOut).Replace('__PB_TOKENS__', $tok).Replace('__PB_REFS__', $ref).Replace('__PB_PKG__', "$PkgName")
}

# Push the agent to a REMOTE machine, run it in the logged-on user's interactive session, pull the report back.
# Needs: your account admin on the remote (c$ + CIM), and SOMEONE logged on there (a locked RDP session is fine).
function Invoke-RemoteShortcutShots {
    param([Parameter(Mandatory)][string]$Machine, [string]$FullName, [string[]]$Tokens, $RefShortcuts, [int]$TimeoutSec = 420)
    $mn = "$Machine".Trim().Split('.')[0]
    if (-not $mn) { return @{ Ok=$false; Message='No machine name.' } }
    if ((Get-PBMachineSplat $mn).Count -eq 0) { return @{ Ok=$false; Message="$mn is THIS machine - use Troubleshoot -> 'Screenshot app shortcuts (this machine)' instead." } }
    $remoteRoot = "\\$mn\c`$\temp\PBShots"
    $taskName = 'PackageBuilderShots'
    $cim = $null
    try {
        Set-PbProgress -Indeterminate -Status "Staging the screenshot agent on $mn..."
        if (Test-Path $remoteRoot) { Remove-Item $remoteRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item (Join-Path $remoteRoot 'out') -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $refNames = @($RefShortcuts | ForEach-Object { "$($_.Name)" } | Where-Object { $_ })
        $agent = New-PBShotsAgentScript -PkgName $FullName -Tokens $Tokens -RefNames $refNames
        [IO.File]::WriteAllText((Join-Path $remoteRoot 'PBShots.ps1'), $agent, (New-Object Text.UTF8Encoding($true)))
        # Who is logged on? (The task must run in THEIR interactive session - no password needed with LogonType Interactive.)
        $user = ''
        try { $user = "$((Get-CimInstance Win32_ComputerSystem -ComputerName $mn -ErrorAction Stop).UserName)" } catch {}
        if (-not $user) {
            $q = @(& quser /server:$mn 2>$null | Select-Object -Skip 1)
            $line = @(@($q | Where-Object { $_ -match '(?i)Active|Aktiv' }) + $q) | Select-Object -First 1
            if ($line) { $user = ("$line" -replace '^[>\s]+','').Split(' ')[0] }
        }
        if (-not $user) { return @{ Ok=$false; Message="$mn has NO logged-on user - screenshots need an interactive session (RDP in once; locked is fine)." } }
        Set-PbProgress -Indeterminate -Status "Starting the agent on $mn as $user (their session; locked is OK)..."
        $cim = New-CimSession -ComputerName $mn -ErrorAction Stop
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\temp\PBShots\PBShots.ps1'
        $pri = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive
        Register-ScheduledTask -CimSession $cim -TaskName $taskName -Action $act -Principal $pri -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -CimSession $cim -TaskName $taskName -ErrorAction Stop
        # Poll for the agent's done flag (each app gets ~1 min worst case; overall bounded).
        $flag = Join-Path $remoteRoot 'out\done.flag'
        $t0 = Get-Date
        while (-not (Test-Path $flag)) {
            if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) { return @{ Ok=$false; Message="Timed out after $TimeoutSec s waiting for the agent on $mn (app hung / no shortcuts found?). Remote leftovers: $remoteRoot" } }
            Set-PbProgress -Indeterminate -Status ("Waiting for screenshots on {0}... {1:mm\:ss}" -f $mn, ((Get-Date) - $t0))
            Start-Sleep -Seconds 5
        }
        Start-Sleep -Seconds 2   # let the last PNG finish writing
        $local = Join-Path (Get-WorkPath ("Screenshots\$FullName\remote\$mn")) (Get-Date -Format 'yyyyMMdd_HHmmss')
        New-Item $local -ItemType Directory -Force | Out-Null
        Copy-Item (Join-Path $remoteRoot 'out\*') $local -Force
        $sum = try { Get-Content (Join-Path $local 'done.flag') -Raw | ConvertFrom-Json } catch { $null }
        $okN = @($sum | Where-Object { $_.Ok }).Count; $all = @($sum).Count
        Write-Log "Remote screenshots: $okN/$all captured on $mn -> $local" Success
        return @{ Ok=$true; Message="$okN/$all shortcut screenshot(s) captured on $mn -> $local (index.html)"; OutDir=$local }
    } catch { return @{ Ok=$false; Message="Remote screenshots on ${mn} failed: $($_.Exception.Message)" } }
    finally {
        if ($cim) {
            try { Unregister-ScheduledTask -CimSession $cim -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
            try { Remove-CimSession $cim } catch {}
        }
        try { if (Test-Path $remoteRoot) { Remove-Item $remoteRoot -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
    }
}
#endregion

