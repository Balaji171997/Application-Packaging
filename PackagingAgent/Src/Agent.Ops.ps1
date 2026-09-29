##############################################################
# Agent.Ops.ps1  -  THE CHANNEL BETWEEN THE AI AND THE TOOL.
#
#   The AI is the brain, this tool is the hands.
#
#   Everything the AI wants - a line number, the content of a section, a modification, a test install - it asks for
#   as a PowerShell command. The tool runs it and hands the output straight back. Nothing about WHAT may be asked is
#   predefined here: only WHERE it may act, HOW LONG it may take, and that every single command is written down.
#
#   AI ---- run_powershell { purpose; intent = read|modify; script } ----> tool executes
#   AI <--- { ok; exitCode; output; durationMs; changedFiles }        ---- tool answers
#
#   The conversation is kept in the transcript (Get-AgentTranscript) so a packager can read exactly what the model
#   asked for, what it got back, and why it decided what it decided. That transcript is the evidence for the package.
##############################################################

# ---- the working area an operation may touch ------------------------------------------------------------------------
# Writes are confined to the package/work folders. Reads are confined to those plus the order and predecessor folders.
function New-AgentOpContext {
    param([string]$PackageFolder, [string]$OrderFolder, [string]$PredecessorFolder, [string]$Policy = '', $Activity, [string]$Stage = '')
    $c = Get-AgentConfig
    if (-not "$Policy".Trim()) { $Policy = "$($c.CommandPolicy)"; if (-not "$Policy".Trim()) { $Policy = 'readwrite' } }
    # a console run publishes its log for the whole runspace, so commands issued deep inside a stage still reach the feed
    if ($null -eq $Activity) { $Activity = $script:AgentActivityLog }
    $work = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { try { Get-WorkPath 'AI' } catch { '' } } else { '' }
    return @{
        PackageFolder = "$PackageFolder".TrimEnd('\')
        OrderFolder = "$OrderFolder".TrimEnd('\')
        PredecessorFolder = "$PredecessorFolder".TrimEnd('\')
        Work = "$work"
        Policy = "$Policy".ToLower()          # readonly = never run a modify command | readwrite = run both
        TimeoutSec = $(if ([int]$c.CommandTimeoutSec -gt 0) { [int]$c.CommandTimeoutSec } else { 180 })
        MaxOutputChars = 24000
        Commands = New-Object System.Collections.Generic.List[object]
        Activity = $Activity          # the shared console log, when one is running
        Stage = "$Stage"
    }
}
# PS 5.1: @() or a comma on a List[object] of PSObjects throws "Argument types do not match" - always .ToArray() first.
function Get-AgentOpCommands { param($Ctx) if (-not $Ctx -or -not $Ctx.Commands) { return @() }; return $Ctx.Commands.ToArray() }
function Get-AgentOpWriteRoots { param($Ctx) return @(@($Ctx.PackageFolder, $Ctx.Work) | Where-Object { "$_".Trim() }) }
# ExtraReadRoots: the package shares, for looking at predecessor candidates. Writing to any UNC path is refused anyway.
function Get-AgentOpReadRoots  { param($Ctx) return @(@($Ctx.PackageFolder, $Ctx.Work, $Ctx.OrderFolder, $Ctx.PredecessorFolder) + @($Ctx.ExtraReadRoots) | Where-Object { "$_".Trim() }) }

# Which paths does this script text touch, and do they sit inside the allowed roots? A best-effort check: it reads the
# literal paths out of the command. It is a guard rail for honest mistakes, not a sandbox - the policy is the real gate.
function Get-AgentOpPathsOutside {
    param([string]$Script, [string[]]$Roots)
    $out = @()
    foreach ($m in [regex]::Matches("$Script", '(?i)(?:[A-Z]:\\|\\\\)[^"''`|;,\r\n\)]{2,240}')) {
        $p = "$($m.Value)".Trim().TrimEnd('\', '.', ',', ')')
        if (-not $p) { continue }
        $full = try { [IO.Path]::GetFullPath($p) } catch { $p }
        $inside = $false
        foreach ($r in $Roots) { if ($full.StartsWith("$r", [StringComparison]::OrdinalIgnoreCase)) { $inside = $true; break } }
        if (-not $inside) { $out += $full }
    }
    return @($out | Sort-Object -Unique)
}

# Run ONE command from the AI. Returns what the tool saw, in the shape the model gets back.
function Invoke-AgentOpCommand {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][string]$Script, [string]$Purpose = '', [string]$Intent = 'read')
    $intent = "$Intent".ToLower(); if ($intent -notin 'read', 'modify') { $intent = 'read' }
    $rec = [ordered]@{ at = (Get-Date -Format 'HH:mm:ss'); purpose = "$Purpose"; intent = $intent; script = "$Script"; ok = $false; output = ''; exitCode = $null; durationMs = 0; refused = '' }

    if ($intent -eq 'modify' -and $Ctx.Policy -eq 'readonly') {
        $rec.refused = 'the session is read-only: modifications are not executed'
        $Ctx.Commands.Add($rec); return @{ ok = $false; refused = $rec.refused; output = '' }
    }
    # WHAT THE COMMAND DOES DECIDES, NOT WHAT IT SAYS IT DOES.
    # `intent` is the model's own description, and a description is not a promise. On a real run a Copy-Item that
    # overwrote the built package script arrived labelled "read", so the wider read-roots were enforced and it ran.
    # So: look at the text. If it writes, it is treated as a write - for the policy gate, for the root check and for
    # change detection - whatever it called itself.
    $looksLikeWrite = [bool]("$Script" -match '(?i)(\b(Set-Content|Add-Content|Out-File|Clear-Content|Copy-Item|Move-Item|Remove-Item|New-Item|Rename-Item|Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Set-Item|Export-Csv|Export-Clixml|Compress-Archive|Expand-Archive|Unblock-File)\b|\[IO\.(File|Directory)\]::(Write|Append|Create|Delete|Move|Copy|Replace)|\|\s*Out-File|>\s*["'']?[A-Za-z]:\\)')
    if ($looksLikeWrite -and $intent -ne 'modify') {
        $intent = 'modify'
        $rec.intent = 'modify'
        $rec.intentCorrected = 'this was sent as a read, but it writes - treated as a modification'
        Write-Log "AI op: a command labelled 'read' writes - treating it as a modification." Warning
        # and a read-only stage must now refuse it, exactly as if it had been labelled honestly
        if ($Ctx.Policy -eq 'readonly') {
            $rec.refused = 'the session is read-only, and this command writes even though it was sent as a read'
            $Ctx.Commands.Add($rec); return @{ ok = $false; refused = $rec.refused; output = '' }
        }
    }
    # LOCAL DISK IS THE AGENT'S WORKSHOP - it is not fenced off. Extract something to a temp folder, copy a file
    # about, write a scratch list: that is ordinary work and there is no reason to stand in the way of it. What IS
    # protected is small and specific, and checked below: the network shares (read-only, always), the predecessor
    # package (it is last version's evidence, not ours to edit) and the built deploy script (edited, never replaced).
    # So only paths on a NETWORK SHARE have to sit inside the roots we were given; anywhere local is the agent's own.
    $roots = @(Get-AgentOpReadRoots -Ctx $Ctx)
    $allPaths = @([regex]::Matches("$Script", '(?i)(?:[A-Z]:\\|\\\\)[^"''`|;,\r\n\)]{2,240}') | ForEach-Object { "$($_.Value)".Trim().TrimEnd('\', '.', ',', ')') })
    $foreignShares = @()
    foreach ($ap in @($allPaths | Where-Object { "$_" -match '^\\\\' } | Sort-Object -Unique)) {
        $inside = $false
        foreach ($r in $roots) { if ("$r".Trim() -and "$ap".StartsWith("$r", [StringComparison]::OrdinalIgnoreCase)) { $inside = $true; break } }
        if (-not $inside) { $foreignShares += $ap }
    }
    if ($foreignShares.Count) {
        $rec.refused = "this command reaches a network share that is not part of this order: $($foreignShares -join '; '). The order folder and the predecessor package are yours to read; other shares are not."
        $Ctx.Commands.Add($rec); return @{ ok = $false; refused = $rec.refused; output = '' }
    }
    # THE SHARES ARE READ-ONLY, ALWAYS. The order shares, the live package library, anything on a UNC path: the agent
    # may read them and copy FROM them, and must never write to them. Those are the team's real repositories - a
    # mistake there is not a broken package, it is a damaged library. Reads are untouched by this.
    if ($looksLikeWrite -or $intent -eq 'modify') {
        # WHICH PATH IS THE TARGET depends on the command. For Copy-Item, -Path is the SOURCE and only -Destination
        # is written - so copying FROM a share to the package is fine and must stay fine. For Set-Content, Out-File,
        # New-Item and Remove-Item, -Path IS what gets written. Move-Item writes at BOTH ends, because the source
        # disappears. Getting this wrong either blocks honest work or lets a share be edited, so it is worth the care.
        $isCopyOnly = [bool]("$Script" -match '(?i)\bCopy-Item\b' -and "$Script" -notmatch '(?i)\b(Set-Content|Add-Content|Out-File|Clear-Content|Move-Item|Remove-Item|New-Item|Rename-Item|Set-ItemProperty)\b')
        $targets = @()
        $rxs = @('(?i)-Destination\s+(?<p>"[^"]+"|''[^'']+''|\S+)',
                 '(?i)\[IO\.(?:File|Directory)\]::(?:Write|Append|Create|Delete|Move|Replace)\w*\(\s*(?<p>"[^"]+"|''[^'']+'')',
                 '(?i)(?:\||>|>>)\s*(?<p>"[^"]+"|''[^'']+'')')
        if (-not $isCopyOnly) { $rxs += '(?i)-(?:LiteralPath|Path|FilePath|OutFile)\s+(?<p>"[^"]+"|''[^'']+''|\S+)' }
        foreach ($rx in $rxs) {
            foreach ($m in [regex]::Matches("$Script", $rx)) { $targets += ($m.Groups['p'].Value.Trim('"', "'")) }
        }
        # THE BUILT DEPLOY SCRIPT IS NOT REPLACED WHOLESALE FROM SOMEWHERE ELSE.
        # It is edited in place, line by line. Copying another script over it - the predecessor's, most temptingly -
        # throws away everything the build just did, and the result looks flawless because it matches the predecessor
        # exactly. That is precisely how a package shipped asking for last version's MSI while this version's sat
        # unused beside it. Change the lines that are wrong; do not overwrite the file.
        $writesWholeScript = @($targets | Where-Object { "$_" -match '(?i)(Invoke-AppDeployToolkit|Deploy-Application)\.ps1\s*$' })
        if ($writesWholeScript.Count -and "$Script" -match '(?i)\b(Copy-Item|Move-Item)\b') {
            $rec.refused = 'this replaces the package''s deploy script with another file. The built script is edited in place, never overwritten - copying the predecessor''s script over it looks correct and silently throws away everything the build did. Change the lines that are wrong instead.'
            Write-Log 'AI op REFUSED - it tried to overwrite the built deploy script with another file.' Warning
            $Ctx.Commands.Add($rec); return @{ ok = $false; refused = $rec.refused; output = '' }
        }
        $onShare = @($targets | Where-Object { "$_" -match '^\\\\' } | Sort-Object -Unique)
        if ($onShare.Count) {
            $rec.refused = "this command writes to a network share ($($onShare -join '; ')). The shares are READ-ONLY: read them and copy FROM them as much as you like, but nothing is ever written back. Work inside the package folder."
            Write-Log "AI op REFUSED - it tried to write to a share: $($onShare -join '; ')" Warning
            $Ctx.Commands.Add($rec); return @{ ok = $false; refused = $rec.refused; output = '' }
        }
        # THE PREDECESSOR PACKAGE IS LAST VERSION'S EVIDENCE. Read it freely; never write into it. It is what every
        # comparison is measured against, and a package library that has been edited is no longer evidence of anything.
        $predRoot = "$($Ctx.PredecessorFolder)".TrimEnd('\')
        if ($predRoot) {
            $intoPred = @($targets | Where-Object { "$_".TrimEnd('\').StartsWith($predRoot, [StringComparison]::OrdinalIgnoreCase) })
            if ($intoPred.Count) {
                $rec.refused = "this writes into the predecessor package ($($intoPred -join '; ')). It is last version's evidence - read it as much as you like, but it is never edited."
                Write-Log "AI op REFUSED - it tried to write into the predecessor package." Warning
                $Ctx.Commands.Add($rec); return @{ ok = $false; refused = $rec.refused; output = '' }
            }
        }
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $before = @{}
    if ($Ctx.PackageFolder -and (Test-Path -LiteralPath $Ctx.PackageFolder)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Ctx.PackageFolder -File -Recurse -Depth 6 -ErrorAction SilentlyContinue)) { $before[$f.FullName] = "$($f.LastWriteTimeUtc.Ticks):$($f.Length)" }
    }
    $tmp = Join-Path $env:TEMP ("agentop_" + [guid]::NewGuid().ToString('N').Substring(0, 10) + '.ps1')
    try {
        # $ErrorActionPreference stays Continue on purpose: the model should SEE the error text, not get an empty answer.
        # Start the command in a sensible working directory, but ONLY if there is one. A read-only ask context has no
    # package folder - nothing has been built yet - and 'Set-Location -LiteralPath ""' throws, which made every
    # command in those stages report failure even though its output was perfectly correct.
    $cwd = @("$($Ctx.PackageFolder)", "$($Ctx.OrderFolder)", "$($Ctx.Work)") |
           Where-Object { "$_".Trim() -and (Test-Path -LiteralPath "$_") } | Select-Object -First 1
    # BOTH of these, and the second one is not optional. Set-Location moves PowerShell's location, which is what
    # cmdlets use - but .NET methods ([IO.File]::ReadAllText, [IO.File]::WriteAllText) resolve relative paths against
    # the PROCESS current directory, which Set-Location does not touch. Without the second line, `Get-Content x.ps1`
    # works and `[IO.File]::ReadAllText('x.ps1')` looks for the file next to the agent instead.
    # That bit us for real: every edit the AI tried failed with "Could not find file", it spent its whole step budget
    # retrying, and then reported a blocker it had already fixed.
    $prelude = if ($cwd) {
        $esc = $cwd -replace "'", "''"
        "Set-Location -LiteralPath '$esc'`r`n[Environment]::CurrentDirectory = '$esc'`r`n"
    } else { '' }
    [IO.File]::WriteAllText($tmp, "$prelude$Script", (New-Object Text.UTF8Encoding $true))
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Command powershell.exe).Source
        $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$tmp`""
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        # WHAT WAS ON SCREEN BEFORE THIS COMMAND. A command that puts a window up is waiting for a click, and a
        # click is never coming - there is nobody sitting in front of this.
        $winBefore = @{}
        try { foreach ($w in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and "$($_.MainWindowTitle)".Trim() })) { $winBefore["$($w.Id)|$($w.MainWindowTitle)"] = $true } } catch {}

        $opStartedAt = Get-Date
        $p = [Diagnostics.Process]::Start($psi)
        $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
        $stopBecause = ''
        $newWindow = ''
        $opSw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited) {
            if ($opSw.Elapsed.TotalSeconds -gt [int]$Ctx.TimeoutSec) { $stopBecause = "it was still going after $($Ctx.TimeoutSec)s"; break }
            # the packager can see this happening and we cannot - let them stop it
            try {
                if ($script:AgentHumanInbox -and $script:AgentHumanInbox.Count) {
                    $said = @($script:AgentHumanInbox.ToArray()); [void]$script:AgentHumanInbox.Clear()
                    $rec.packagerSaid = @($said)
                    $stopBecause = "the packager stopped it: $(@($said) -join ' / ')"
                    break
                }
            } catch {}
            # a window that was not there before this command started belongs to this command
            try {
                foreach ($w in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and "$($_.MainWindowTitle)".Trim() })) {
                    if ($winBefore["$($w.Id)|$($w.MainWindowTitle)"] -or $w.Id -eq $PID) { continue }
                    $newWindow = "$($w.ProcessName): $($w.MainWindowTitle)"
                    $stopBecause = "it opened a window ('$newWindow') and waited for somebody to click it - nobody is sitting here"
                    break
                }
            } catch {}
            if ($stopBecause) { break }
            Start-Sleep -Milliseconds 400
        }
        if ($stopBecause) {
            $rec.refused = 'stopped'; $rec.stoppedBecause = $stopBecause
            # KILL THE WHOLE TREE. Killing only powershell.exe leaves whatever it launched running - which is how
            # three installer dialogs ended up sitting on a packager's screen with nothing left to close them.
            try { & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F 2>&1 | Out-Null } catch {}
            try { if (-not $p.HasExited) { $p.Kill() } } catch {}
        } else {
            $rec.exitCode = $p.ExitCode
        }
        # HARVEST THE OUTPUT WITH A BOUND, NEVER WITH .Result.
        # ReadToEndAsync completes when the PIPE closes, not when the process exits - and a child that inherited the
        # handle keeps it open. So powershell.exe finished, WaitForExit returned true, and .Result then blocked
        # FOREVER on an installer still running in the background. The whole run stopped there: no timeout could fire,
        # because the timeout had already passed, and no further model call was ever made.
        $gotOut = try { $so.Wait(5000) } catch { $false }
        $gotErr = try { $se.Wait(1000) } catch { $false }
        $txt = if ($gotOut) { "$($so.Result)" } else { '' }
        $err = if ($gotErr) { "$($se.Result)" } else { '' }
        if (-not $gotOut) {
            $txt = "(the output could not be collected: something this command started is still running and holding the pipe open. It was stopped.)"
            try { & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F 2>&1 | Out-Null } catch {}
        }
        $rec.hadErrors = [bool]("$err".Trim())
        if ($rec.hadErrors) { $txt = "$txt`n[errors]`n$err" }
        if ($stopBecause) { $txt = "(stopped: $stopBecause)`n$txt" }
        $rec.output = "$txt".Trim()
        $rec.ok = (-not $stopBecause -and $gotOut -and $rec.exitCode -eq 0 -and -not $rec.hadErrors)
        # LET IT SETTLE, THEN LOOK - AND LOOK TWICE.
        # The machine the instant a command returns is not the machine that matters. A window takes a second or two
        # to appear, so an immediate glance reports "nothing happened" for something that is about to put a dialog
        # up. But a fixed wait on every command would add minutes across a run for a Get-Content.
        # So: glance once; if nothing new is there, return immediately and cost nothing. If something IS there, wait
        # and look again - because the second look is what tells you WHICH kind of something it is:
        #   gone by the second look    a splash or progress window that closes itself - harmless
        #   there at both              it is waiting for a click, and no click is coming
        #   a process at both          still working, or stuck - either way the AI needs to know
        $look = {
            $w = @(); $pr = @()
            try { $w = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and "$($_.MainWindowTitle)".Trim() -and -not $winBefore["$($_.Id)|$($_.MainWindowTitle)"] -and $_.Id -ne $PID }) } catch {}
            try { $pr = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.StartTime -gt $opStartedAt }) } catch {}
            return @{ Windows = $w; Procs = $pr }
        }
        try {
            Start-Sleep -Milliseconds 1200
            $first = & $look
            if (@($first.Windows).Count -or @($first.Procs).Count) {
                $rec.afterTheCommand = [ordered]@{ lookedAgainAfterSec = 6 }
                Start-Sleep -Seconds 6
                $second = & $look
                $stillOpen = @($second.Windows | ForEach-Object { "$($_.ProcessName): $($_.MainWindowTitle)" })
                $closedItself = @(@($first.Windows | ForEach-Object { "$($_.ProcessName): $($_.MainWindowTitle)" }) | Where-Object { $stillOpen -notcontains $_ })
                $rec.afterTheCommand.windowsStillOpen = $stillOpen
                $rec.afterTheCommand.windowsThatClosedThemselves = $closedItself
                $rec.afterTheCommand.stillRunning = @($second.Procs | Select-Object -First 12 | ForEach-Object { "$($_.ProcessName) ($($_.Id))" })
                $rec.afterTheCommand.note = @(
                    $(if ($stillOpen.Count) { "$($stillOpen.Count) window(s) were STILL open six seconds after this command finished - '$($stillOpen[0])'. Nothing is going to click them." })
                    $(if ($closedItself.Count) { "$($closedItself.Count) window(s) appeared and closed themselves - a splash or progress window, not a prompt." })
                    $(if (@($second.Procs).Count) { "$(@($second.Procs).Count) process(es) this command started are still running." })
                ) | Where-Object { $_ } | ForEach-Object { $_ }
                if ($stillOpen.Count) { $rec.leftOnScreen = $stillOpen }
                # Only tidy up after something WE stopped. If the command ran to completion and left something
                # standing, that is the AI's to decide about - it can see it now, and killing it here would be the
                # tool deciding. What it must never be is invisible.
                if ($stopBecause) {
                    foreach ($w in $second.Windows) { try { [void]$w.CloseMainWindow() } catch {} }
                    Start-Sleep -Milliseconds 800
                    foreach ($w in $second.Windows) { try { $w.Refresh(); if (-not $w.HasExited) { Stop-Process -Id $w.Id -Force -ErrorAction SilentlyContinue } } catch {} }
                    $rec.afterTheCommand.cleanedUp = $true
                }
            }
        } catch {}
    } catch { $rec.output = "$($_.Exception.Message)"; $rec.refused = 'could not start powershell' }
    finally { try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {} }
    $sw.Stop(); $rec.durationMs = [int]$sw.ElapsedMilliseconds

    if ("$($rec.output)".Length -gt $Ctx.MaxOutputChars) { $rec.output = "$($rec.output)".Substring(0, $Ctx.MaxOutputChars) + "`n...(output truncated)" }
    # WATCH FOR CHANGES ON EVERY COMMAND, not only the ones labelled 'modify'. The intent is the model's own
    # description of what it is about to do, and a description is not a guarantee: on a real run a Copy-Item that
    # overwrote the built package script arrived labelled as a read, so nothing was recorded and the report said
    # "0 files changed" while the package had just been replaced. What the command DID is the only reliable signal.
    $changed = @()
    if ($Ctx.PackageFolder -and (Test-Path -LiteralPath $Ctx.PackageFolder)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Ctx.PackageFolder -File -Recurse -Depth 6 -ErrorAction SilentlyContinue)) {
            $sig = "$($f.LastWriteTimeUtc.Ticks):$($f.Length)"
            if (-not $before.ContainsKey($f.FullName) -or $before[$f.FullName] -ne $sig) { $changed += $f.FullName.Substring($Ctx.PackageFolder.Length).TrimStart('\') }
        }
    }
    $rec.changedFiles = @($changed)
    $Ctx.Commands.Add($rec)
    # this is the AI speaking to the machine - logged as AI, never as a tool step
    Add-AgentActivity -Log $Ctx.Activity -Actor 'AI' -Stage "$($Ctx.Stage)" -Kind 'command' -Text "$Purpose" `
                      -Command "$Script" -Output "$($rec.output)" -Changed @($changed)
    Write-Log "AI op [$intent] $($rec.purpose) -> $(if ($rec.ok) { 'ok' } else { 'failed' })$(if ($changed.Count) { ", changed: $($changed -join ', ')" })"
    return @{ ok = $rec.ok; exitCode = $rec.exitCode; hadErrors = [bool]$rec.hadErrors; output = "$($rec.output)"; durationMs = $rec.durationMs; changedFiles = @($changed); refused = "$($rec.refused)" }
}

# The ONE tool the model needs to reach the machine. Everything else it wants, it writes as PowerShell.
function Get-AgentOpTools {
    param([Parameter(Mandatory)]$Ctx)
    return @(
        @{ Ctx = $Ctx
           Decl = (New-AgentFunctionDeclaration -Name 'run_powershell' -Description @'
Run a Windows PowerShell 5.1 command on the packaging machine and get its output back. This is how you look at
anything and how you change anything: read a file with line numbers, search a script, list a folder, inspect an MSI,
edit the package script, copy a file into SupportFiles. Write real PowerShell and OUTPUT what you want to see
(Write-Output / the expression itself) - whatever the command prints is what you get back.
Set intent to "modify" for anything that writes, renames, copies or deletes; "read" for everything else.
You may call this as often as you need before you submit your result.
'@ -Parameters @{ type = 'OBJECT'; properties = @{
                purpose = @{ type = 'STRING'; description = 'one short line: why you are running this, in plain words for the packager' }
                intent  = @{ type = 'STRING'; description = 'read | modify' }
                script  = @{ type = 'STRING'; description = 'the PowerShell. The working directory is already the package folder, so relative paths work.' } }
                required = @('purpose', 'script') })
           Run = { param($a, $c) return (Invoke-AgentOpCommand -Ctx $c -Script "$($a.script)" -Purpose "$($a.purpose)" -Intent "$($a.intent)") } }
    )
}

# ---- the activity log: WHO did what, never blurred ---------------------------------------------------------------------
#   AI    the remote expert - its reasoning, and the commands IT asked for
#   TOOL  the on-site admin - what this tool did on its own (snapshot, trial install, build, file placement)
#   YOU   the packager - approvals and decisions
# An AI command and a tool operation are never rendered or recorded as the same thing: mixing them is what produced a
# command line with two /i switches, and it makes the flow unreadable.
function New-AgentActivityLog { $l = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)); return , $l }
function Add-AgentActivity {
    param($Log, [ValidateSet('AI', 'TOOL', 'YOU')][string]$Actor = 'TOOL', [string]$Stage = '', [string]$Text = '',
          [string]$Command = '', [string]$Output = '', [string]$Kind = 'step', [string[]]$Changed = @())
    if ($null -eq $Log) { return }
    [void]$Log.Add([ordered]@{ at = (Get-Date -Format 'HH:mm:ss'); actor = $Actor; stage = "$Stage"; kind = "$Kind"
                               text = "$Text"; command = "$Command"; output = "$Output"; changed = @($Changed) })
}

# ---- transcript: what the model asked, what it got, what it concluded -------------------------------------------------
# PS 5.1: 'return $list' ENUMERATES the collection - an empty List comes back as $null and a filled one as loose
# objects. The comma wrapper is what makes a function hand back the list itself.
function New-AgentTranscript { $l = New-Object System.Collections.Generic.List[object]; return , $l }
# Adds in place and returns NOTHING on purpose - returning the list would unroll it at every call site.
function Add-AgentTranscriptTurn {
    param([Parameter(Mandatory)]$Transcript, [string]$Stage, [string]$Thinking, $Commands, [string]$Result)
    $Transcript.Add([ordered]@{ at = (Get-Date -Format 'HH:mm:ss'); stage = "$Stage"; thinking = "$Thinking"
                                commands = @(@($Commands) | ForEach-Object { [ordered]@{ purpose = "$($_.purpose)"; intent = "$($_.intent)"; script = "$($_.script)"; ok = [bool]$_.ok; output = "$($_.output)"; changedFiles = @($_.changedFiles); refused = "$($_.refused)" } })
                                result = "$Result" })
}
function Format-AgentTranscriptText {
    param([Parameter(Mandatory)]$Transcript)
    $sb = New-Object Text.StringBuilder
    foreach ($t in $Transcript.ToArray()) {
        [void]$sb.AppendLine("[$($t.at)] $($t.stage)")
        if ("$($t.thinking)".Trim()) { [void]$sb.AppendLine("  AI: $("$($t.thinking)" -replace "`r?`n", "`n       ")") }
        foreach ($c in @($t.commands)) {
            [void]$sb.AppendLine("  AI asks the tool ($($c.intent)): $($c.purpose)")
            foreach ($l in @("$($c.script)" -split "`r?`n")) { [void]$sb.AppendLine("      | $l") }
            $o = "$($c.output)"; if ($o.Length -gt 600) { $o = $o.Substring(0, 600) + ' ...' }
            [void]$sb.AppendLine("  tool answers$(if (-not $c.ok) { ' (FAILED)' }): $($o -replace "`r?`n", "`n                 ")")
            if (@($c.changedFiles).Count) { [void]$sb.AppendLine("  tool changed: $(@($c.changedFiles) -join ', ')") }
        }
        if ("$($t.result)".Trim()) { [void]$sb.AppendLine("  AI concludes: $($t.result)") }
        [void]$sb.AppendLine('')
    }
    return $sb.ToString().TrimEnd()
}
