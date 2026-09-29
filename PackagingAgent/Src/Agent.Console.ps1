##############################################################
# Agent.Console.ps1  -  THE AGENT CONSOLE.
#
#   One window, one button. You give it an order folder and press Run; the agent works the flow and you watch it
#   happen. It stops only where a human is genuinely needed - before it installs on this machine.
#
#   The feed shows WHO did what, and never blurs the two:
#       AI    the remote expert  - its reasoning, and the commands IT asked the tool to run
#       TOOL  the on-site admin  - what this tool did itself: snapshots, trial installs, building the package
#       YOU   the packager       - the approvals you gave
##############################################################

$script:AgentConsoleColors = @{
    AI    = '#56C8D6'   # cyan   - the remote expert
    TOOL  = '#6A9955'   # green  - our hands on the machine
    YOU   = '#E0BE7C'   # amber  - the human
    Error = '#F48771'
    Muted = '#8A93A0'
    Text  = '#E7E9ED'
}

function New-AgentFeedEntry {
    param([Parameter(Mandatory)]$Item)
    # A RECORD, NOT A CHAT LINE. What matters when you read a run back is what KIND of thing happened - a decision is
    # not a command, a command is not its result, a question is not a note. The actor alone never told you that.
    $type = if ("$($Item.kind)" -eq 'error') { 'PROBLEM' }
            elseif ("$($Item.kind)" -eq 'command') { 'COMMAND' }
            elseif ("$($Item.actor)" -eq 'YOU') { 'ANSWER' }
            elseif ("$($Item.actor)" -eq 'AI') { 'DECISION' }
            elseif ("$($Item.output)".Trim() -or @($Item.changed).Count) { 'RESULT' }
            else { 'NOTE' }
    $col = switch ($type) {
        'DECISION' { '#C58AF9' } 'COMMAND' { '#5BA97A' } 'RESULT' { '#8A93A0' }
        'ANSWER'   { '#E0BE7C' } 'PROBLEM' { '#F48771' } default { '#5A616B' }
    }

    $row = New-Object Windows.Controls.Border
    $row.BorderThickness = '2,0,0,0'; $row.Padding = '9,1,0,0'; $row.Margin = '0,0,0,11'
    $row.BorderBrush = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($col)))
    $stack = New-Object Windows.Controls.StackPanel
    $row.Child = $stack

    $when = New-Object Windows.Controls.TextBlock
    $when.Text = "$type   $($Item.at)$(if ("$($Item.stage)".Trim()) { "  ·  $($Item.stage)" })"
    $when.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($col)))
    $when.FontSize = 10; $when.Margin = '0,0,0,2'
    [void]$stack.Children.Add($when)

    if ("$($Item.text)".Trim()) {
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = "$($Item.text)"; $t.Foreground = $script:AgentConsoleColors.Text; $t.FontSize = 12.5
        $t.TextWrapping = 'Wrap'
        [void]$stack.Children.Add($t)
    }
    # the AI's command, and what the tool answered - shown as what they are, never merged into one line
    if ("$($Item.command)".Trim()) {
        $b = New-Object Windows.Controls.Border
        $b.Background = '#111317'; $b.BorderBrush = '#2A2F38'; $b.BorderThickness = '1'; $b.CornerRadius = '3'
        $b.Padding = '8,5'; $b.Margin = '0,4,0,0'; $b.HorizontalAlignment = 'Stretch'
        $c = New-Object Windows.Controls.TextBlock
        $c.Text = "$($Item.command)".Trim(); $c.Foreground = '#D7FFD7'; $c.FontFamily = 'Consolas'; $c.FontSize = 11.5; $c.TextWrapping = 'Wrap'
        $b.Child = $c; [void]$stack.Children.Add($b)
    }
    if ("$($Item.output)".Trim()) {
        $o = "$($Item.output)".Trim()
        if ($o.Length -gt 1200) { $o = $o.Substring(0, 1200) + "`n...(truncated - the full text is in the report)" }
        $ob = New-Object Windows.Controls.TextBlock
        $ob.Text = $o; $ob.Foreground = $script:AgentConsoleColors.Muted; $ob.FontFamily = 'Consolas'; $ob.FontSize = 11
        $ob.TextWrapping = 'Wrap'; $ob.Margin = '0,3,0,0'
        [void]$stack.Children.Add($ob)
    }
    if (@($Item.changed).Count) {
        $ch = New-Object Windows.Controls.TextBlock
        $ch.Text = "changed: $(@($Item.changed) -join ', ')"; $ch.Foreground = $script:AgentConsoleColors.TOOL
        $ch.FontSize = 11; $ch.Margin = '0,2,0,0'; $ch.TextWrapping = 'Wrap'
        [void]$stack.Children.Add($ch)
    }
    return $row
}

# One stage = one background runspace. The scripts below are the ONLY place a stage is started, so the console never
# has to know how a stage works - it just watches the activity log and the returned sheet.
function Get-AgentStageScript {
    param([Parameter(Mandatory)][string]$Id)
    switch ($Id) {
        'evaluate' { return @'
param($a, $box)
$log = $a.activity; $script:AgentActivityLog = $log; $sheet = $a.sheet
# IS THIS MACHINE FIT TO TEST ON? If a copy of the application is already here, the before/after diff is worthless.
# The AI decides what each match really is and what must come off; the tool runs the uninstall commands.
$box.Progress = 'checking what is already installed'
$mp = Invoke-AgentMachinePrep -Sheet $sheet -Execute -Progress { param($t) $box.Progress = "$t" }
$sheet.machinePrep = $mp
if (@($mp.found).Count) {
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Something related is already on this machine: $((@($mp.found) | ForEach-Object { "$($_.displayName) $($_.version)" }) -join ' | '). Whatever is here now will be in the before-picture, so it has to be dealt with first."
    if ($mp.decision) { Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "$($mp.decision.summary)" }
    if (@($mp.notInThePlan).Count) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Left installed, because the plan did not ask for it to go: $(@($mp.notInThePlan) -join ', '). The AI is told, when it reads the test." }
    foreach ($r in @($mp.removed)) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind $(if ($r.ok) { 'step' } else { 'error' }) `
            -Text "$(if ($r.ok) { 'Removed' } else { 'COULD NOT remove' }) '$($r.displayName)' before testing" -Command "$($r.command)"
    }
    if (@($mp.stillInstalled).Count) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "$(@($mp.stillInstalled) -join ', ') is still installed, so the before/after comparison will be less clear about what THIS installer did." }
} else {
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'The machine is clean - nothing related is installed.'
}

# WHAT IS REALLY INSIDE THE WRAPPER, when the AI asked for it. The listing at intake only gave names; this pulls the
# MSIs out and reads each one's true identity, which is the only way route 5 can be argued honestly. It costs a minute
# or two on a multi-gigabyte installer, so it happens on request and never by default.
$ev = $sheet.plan.evaluate
$wantExtract = [bool]($ev.extractMsi.wanted -and "$($ev.extractMsi.why)".Trim())
if ($wantExtract -and @(Get-AgentList $sheet.extractedMsis.candidates).Count) {
    # prepare already took them out, so the plan's lines can name them
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Already taken out of the wrapper before the test: $((@($sheet.extractedMsis.candidates) | ForEach-Object { "$($_.file) ('$($_.productName)' $($_.productVersion))" }) -join ', ')"
} elseif ($wantExtract) {
    $exeForExtract = @(@(Get-AgentList $sheet.sources.archiveInspection) | Where-Object { @($_.msiCandidates).Count } | Select-Object -First 1)
    if (-not $exeForExtract.Count) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Extraction was asked for, but no installer here has a listable MSI inside it - nothing to extract.'
    } else {
        $instName = "$($exeForExtract[0].installer)"
        $instPath = @(Get-ChildItem -LiteralPath "$($sheet.folder)" -File -Recurse -Depth 8 -Filter $instName -ErrorAction SilentlyContinue | Select-Object -First 1)
        Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "Looking inside $instName, because $($ev.extractMsi.why)"
        if (-not $instPath.Count) {
            Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "Cannot find $instName to extract from."
        } else {
            $box.Progress = "extracting the MSI(s) from $instName"
            $exWork = Join-Path $env:TEMP ('agent-extract-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $ef = Get-AgentExtractedMsiFacts -InstallerPath $instPath[0].FullName -WorkFolder $exWork `
                    -ExpectedName "$($sheet.identity.app)" -ExpectedVersion "$($sheet.identity.version)" -ExpectedVendor "$($sheet.identity.vendor)"
            $sheet.extractedMsis = $ef
            if (@($ef.candidates).Count) { $sheet.extractedDir = $exWork }
            if (@($ef.candidates).Count) {
                Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "$(@($ef.candidates).Count) MSI(s) came out in $($ef.seconds)s:"
                foreach ($cm in @($ef.candidates)) {
                    $own = if ($cm.manufacturerOverlapsVendor) { 'same vendor as the order' } else { "a different vendor ($($cm.manufacturer))" }
                    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "   $($cm.file) - '$($cm.productName)' $($cm.productVersion), $($cm.sizeMB) MB, $own"
                }
                Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text 'Which of these is the application - if any - is for the AI to say; a different vendor means a bundled prerequisite, not the application.'
            } else {
                Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "Nothing could be extracted: $($ef.note)"
            }
        }
    }
}

# OLD-VERSUS-NEW, when the AI asked for it: install the PREVIOUS package first, so the diff shows what actually
# changed between the versions - product codes, paths, registry names - instead of what a clean machine gained.
$pred = if ($sheet.history -and "$($sheet.history.predecessor.path)".Trim()) { "$($sheet.history.predecessor.path)" } else { '' }
# the AI has to have written down WHAT the comparison answers - "yes" without a reason is not a reason
$compare = [bool]($ev.compareWithPredecessor -and $pred -and "$($ev.whyCompare)".Trim())
$before = $null
if ($compare) {
    # INSTALL IT, MEASURE IT, TAKE IT OFF, MEASURE WHAT IT LEFT.
    # Leaving the old version ON and installing over it looks like the real upgrade, but it measures the wrong
    # thing. A package installs its application AND the shared pieces it needs - runtimes, redistributables,
    # common components - and its UNINSTALL deliberately leaves those behind, because removing a shared runtime
    # breaks whatever else on the machine depends on it. So those pieces sit there afterwards, and when the NEW
    # version installs it finds them already present and quietly skips them. They never appear in the diff, and the
    # report then understates what this package actually puts on a clean machine.
    # Measuring each step separately is the only way to know: what the old one installs, what its removal leaves,
    # and therefore what the new one's diff is blind to.
    Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "Installing the previous version first, so the comparison shows what actually changed between them. $($ev.whyCompare)"
    $box.Progress = 'snapshotting this machine before anything goes on it'
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Snapshotting the machine as it stands, before anything is installed - everything after this is measured against it.'
    $clean = Get-MachineSnapshot
    $vendP = "$($sheet.identity.vendor)"; $appP = "$($sheet.identity.app)"

    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Installing the previous package first ($(Split-Path -Leaf $pred))."
    $box.Progress = 'installing the previous package'
    $pi = Install-AgentPredecessorPackage -PredecessorPath $pred -Progress { param($t) $box.Progress = "$t" }
    $sheet.predecessorInstall = $pi
    if ($pi.ok) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "The previous version is installed (exit $($pi.exitCode), $($pi.durationSec)s, via $($pi.ranWith))."
        $box.Progress = 'snapshotting with the previous version on'
        $withOld = Get-MachineSnapshot
        try {
            $sheet.predecessorFootprint = Compare-MachineSnapshot -Before $clean -After $withOld -AppVendor $vendP -AppName $appP
            Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "That is what the PREVIOUS package puts on a clean machine - $(@($sheet.predecessorFootprint.Programs.Added).Count) program entr(ies), including anything it bundles."
        } catch {}

        $box.Progress = 'removing the previous version again'
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Now taking the previous version off again, so the new one is measured on a machine it has not already been installed on.'
        $pu = Uninstall-AgentPredecessorPackage -InstallResult $pi -Progress { param($t) $box.Progress = "$t" }
        $sheet.predecessorUninstall = $pu
        $box.Progress = 'snapshotting what the uninstall left behind'
        $afterRemoval = Get-MachineSnapshot
        try {
            $sheet.predecessorLeftovers = Compare-MachineSnapshot -Before $clean -After $afterRemoval -AppVendor $vendP -AppName $appP
            $leftN = @($sheet.predecessorLeftovers.Programs.Added).Count
            if ($leftN) {
                Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "THE UNINSTALL LEFT $leftN PROGRAM ENTR(IES) BEHIND: $((@($sheet.predecessorLeftovers.Programs.Added) | ForEach-Object { "$($_.Info.DisplayName)" } | Select-Object -First 6) -join ', '). These are the shared pieces a package does not remove. The new version will find them already there and SKIP installing them, so they will NOT show up in its diff - read that diff knowing this list is missing from it."
            } else {
                Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'The uninstall left nothing behind - the machine is back where it started, so the new version is measured honestly.'
            }
        } catch {}
        $before = $afterRemoval
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Baseline for the new version: this machine with the previous version removed.'
    }
    else { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "Could not install the previous package: $($pi.error). Falling back to a clean baseline." }
}
if (-not $before) {
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Taking the baseline snapshot of this machine.'
    $box.Progress = 'baseline snapshot'
    $before = Get-MachineSnapshot
}
# note every MSI already lying about, so we can tell which ones THIS installer drops while it runs
$msiBase = Get-AgentMsiWatchBaseline
# and every autostart point that already exists, so the services, tasks and run keys the install ADDS stand out -
# that delta is where the auto-updater is, and it costs about eight seconds
$autoBase = $null
if (Get-Command Get-AgentAutostartFacts -ErrorAction SilentlyContinue) {
    $box.Progress = 'noting the autostart points that already exist'
    $autoBase = Get-AgentAutostartFacts
    if ("$($autoBase.readBy)" -eq 'autorunsc') { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Wrote down what already starts on this machine - $(@($autoBase.services).Count) services, $(@($autoBase.tasks).Count) scheduled tasks, $(@($autoBase.logon).Count) logon entries - so anything the installer adds stands out afterwards. That is usually where the auto-updater is." }
}
$p = $a.proposal
# ASK THE INSTALLER WHAT IT ACCEPTS, before guessing at switches. A packager types /? first; so should we. This runs
# on the test machine, moments before the same file is installed anyway, and the output tells the AI which parameters
# really exist - for silence, yes, but also for suppressing prompts, holding back the restart and logging.
# Most installers answer with a WINDOW listing their switches: it is photographed, its words are read, and the picture
# goes to the AI with the judgement and the retry. The probe closes everything it started.
if ("$($p.Installer)".Trim() -and (Test-Path -LiteralPath "$($p.Installer)") -and "$($p.Installer)" -match '(?i)\.exe$') {
    $box.Progress = 'asking the installer what parameters it accepts'
    try {
        $hlp = @(Get-AgentInstallerHelpLook -ExePath "$($p.Installer)" -Progress { param($t) $box.Progress = "$t" })
        $best = @($hlp | Where-Object { $_.looksLikeHelp }) | Select-Object -First 1
        $sheet.installerHelp = [ordered]@{ installer = (Split-Path -Leaf "$($p.Installer)"); answers = @($hlp)
            note = $(if ($best) { "the installer answered $($best.switch) with its own parameter list$(if ($best.screenshot) { ' in a window - photographed, and its text read' })" } else { 'the installer gave no parameter list for any help switch - going on the playbook, the documents and the predecessor' }) }
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "$(Split-Path -Leaf "$($p.Installer)"): $($sheet.installerHelp.note)." -Command $(if ($best) { (@("$($best.consoleText)") + @($best.windowText) | Where-Object { "$_".Trim() }) -join "`n" } else { '' })
    } catch {
        $sheet.installerHelp = [ordered]@{ installer = (Split-Path -Leaf "$($p.Installer)"); answers = @(); note = "could not ask: $($_.Exception.Message.Split([char]10)[0])" }
    }
}
# What the plan said the test has to prove - shown so the packager knows what to look for too.
if (Test-AgentIsReuse -Sheet $sheet) {
    Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text 'Installing it the way the previous version does - what matters now is what comes out different.'
}
$mustProve = @(Get-AgentList $ev.mustProve)
if ($mustProve.Count) { Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "This test has to show: $($mustProve -join '; ')" }
# RECORD THE INSTALL, when the AI asked for it. For a wrapper nothing can look inside - InstallShield, Wise - the
# child process command lines are the only way to learn what it really ran and with which switches.
$trace = $null
$wantTrace = [bool]($ev.traceTheInstall.wanted -and "$($ev.traceTheInstall.why)".Trim())
if ($wantTrace) {
    Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "Recording every process this installer starts, because $($ev.traceTheInstall.why)"
    $box.Progress = 'starting the process recorder'
    $trace = Start-AgentProcessTrace
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind $(if ($trace.ok) { 'info' } else { 'error' }) -Text $(if ($trace.ok) { "Recording what the installer does ($($trace.note))." } else { "Not recording: $($trace.note)" })
}
Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Now installing $($p.Name). Trying $(@($a.candidates).Count) command$(if (@($a.candidates).Count -ne 1) { 's' }) in order until one installs without asking anybody anything. Each one is watched while it works - a window alone is not a failure; when something sits still with a window up, the screen is photographed and the AI says what it is."
if ("$($p.Installer)" -match '(?i)\.msi$' -or @($a.candidates | Where-Object { "$($_.command)" -match '(?i)TRANSFORMS=' }).Count) {
    $md = Get-AgentTemplateMsiDefaults
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "An MSI is run the way Start-ADTMsiProcess will run it in the package: the template's own '$($md.SilentParams)' and $($md.LoggingOptions) logging are added (Config\config.psd1), so they never need writing into the script."
}
# THE AI LOOKS AT THE SCREEN when the hands cannot tell working from waiting
$script:AgentJudgeSheet = $sheet
$sheet.trialStartedAt = (Get-Date).AddSeconds(-5).ToString('o')   # what the AI is told about the machine starts here
$judge = { param($lk) Invoke-AgentScreenJudge -Sheet $script:AgentJudgeSheet -Look $lk }
# every place an installer or transform may come from: the order, what was extracted, what gets caught while a vendor
# installer runs, and the previous package (read-only)
$sheet.capturedDir = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath ("Caught\" + ("$($sheet.package)" -replace '[\\/:*?"<>|]', '_')) } else { Join-Path $env:TEMP "PackagingAgent\Caught\$($sheet.package)" }
$look = @(@("$($sheet.folder)") + @(Get-AgentInstallerRoots -Sheet $sheet))
$showRan = {
    param($att, [string]$label)
    # WHAT THE AI ASKED FOR, AND WHAT REALLY RAN - side by side, so a line that ran differently from what was written
    # (a transform dropped, a path changed) is visible to everyone
    $e = if ($null -ne $att.exitCode) { " (exit $($att.exitCode))" } elseif ("$($att.error)".Trim()) { " ($($att.error))" } else { '' }
    $w = if (@($att.windowsSeen).Count) { "  window: $(@($att.windowsSeen)[0])" } else { '' }
    $lf = $att.msiLogFacts
    $logNote = if ($lf -and $lf.exists) { "  |  MSI log: $(if ("$($lf.outcome)".Trim()) { "$($lf.product) - $($lf.outcome)" } else { "return $($lf.returnValue)" })$(if (@($lf.transformsApplied).Count) { "; transform applied: $(@($lf.transformsApplied) -join ', ')" })$(if (@($lf.transformsNotSeen).Count) { "; TRANSFORM NOT SEEN IN THE LOG: $(@($lf.transformsNotSeen) -join ', ')" })" } else { '' }
    $asked = if ("$($att.aiCommand)".Trim()) { "AI's command: $($att.aiCommand)`nran:          $($att.command)" } else { "ran: $($att.command)" }
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind $(if ($att.verdict -in 'silent', 'progress') { 'step' } else { 'error' }) `
        -Text ("$label`: $($att.verdict)$e after $($att.durationSec)s$w$logNote") -Command $asked
    if (@($att.neededIntervention).Count) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "   NOT SILENT - it needed someone to close: $(@($att.neededIntervention) -join ' | ')" }
    if (@($att.templateDefaultsAdded).Count) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "   added by the template, as in the package: $(@($att.templateDefaultsAdded) -join ' ')" }
    foreach ($mc in @(@($att.msiCaptured) | Where-Object { $_ })) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "   caught while it ran: $($mc.file) ($($mc.sizeMB) MB, unpacked at $($mc.unpackedAt))" }
}
# GIVE THE MACHINE BACK - before a further attempt, and at the end of every test round, whatever happened
$script:AgentBaseline = $before
$cleanup = {
    param([string]$why)
    $box.Progress = "cleaning up: $why"
    $c = Invoke-AgentMachineCleanup -Before $script:AgentBaseline -Sheet $script:AgentJudgeSheet -Progress { param($t) $box.Progress = "$t" } -Judge $judge -Why $why
    if (@($c.programsRemoved).Count -or @($c.foldersRemoved).Count -or @($c.otherRemoved).Count -or @($c.couldNotRemove).Count) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind $(if ($c.clean) { 'step' } else { 'error' }) `
            -Text "Cleaned up $why`: $(@(@($c.programsRemoved) + @($c.foldersRemoved) + @($c.otherRemoved)).Count) item(s) removed$(if (@($c.couldNotRemove).Count) { "; NOT removed: $(@($c.couldNotRemove) -join ' | ')" })$(if ($c.clean) { ' - the machine is back to its baseline.' } else { " - $([int]$c.left.count) item(s) remain." })"
    }
    $script:AgentJudgeSheet.cleanups = @(@(Get-AgentList $script:AgentJudgeSheet.cleanups) + @($c))
    return $c
}
$showLooks = {
    param($att)
    foreach ($lk in @(@($att.looks) | Where-Object { $_ })) {
        Add-AgentActivity -Log $log -Actor $(if ("$($lk.by)" -eq 'ai') { 'AI' } else { 'TOOL' }) -Stage 'evaluate' -Kind $(if ("$($lk.decided)" -eq 'stop') { 'error' } else { 'info' }) `
            -Text "at $($lk.atSec)s ($($lk.phase)): $(@($lk.windows) -join ' | ')$(if ("$($lk.whatItIs)".Trim()) { " - $($lk.whatItIs)" }) -> $($lk.decided)"
    }
    if (@($att.windowsAfterInstall).Count) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "After the installer ended it left open: $(@($att.windowsAfterInstall) -join ' | ') - photographed, then closed." }
}
$cands = @($a.candidates)
# The composed line - every intent together, not just silence - is what we want proven, so it goes first unless the
# AI already put it there. Everything else stays as a fallback in the order the AI ranked it.
# WHAT GETS RUN, AND IN WHAT ORDER, IS THE AI'S LIST - the tool does not add to it or reorder it.
# This used to inject two candidates of its own: the AI's composed command line, and the predecessor's command on a
# reuse. Both were the tool deciding, and both went wrong - the composed line still named msiexec and produced a
# duplicated /i (1639), and the predecessor "command" was actually a display string, which msiexec answered with its
# usage dialog and then sat waiting for a click.
# The AI already knows both of those things: it writes composedCommand itself, and the predecessor's install line is
# in front of it. If one of them should be tried first, it puts it first. The tool runs the list as given.
# The lines the machine proved, in the shape the build reads them.
$mkProven = {
    param($tr)
    if (-not $tr -or -not $tr.found) { return @() }
    if (@($tr.steps).Count) { return @(@($tr.steps) | ForEach-Object { [ordered]@{ order = $_.order; installer = "$($_.installer)"; arguments = "$($_.arguments)"; commandLine = "$($_.aiCommand)"; purpose = "$($_.purpose)" } }) }
    $w = $tr.winner
    return @([ordered]@{ order = 1; installer = "$($w.installer)"; arguments = "$($w.arguments)"; commandLine = "$($w.aiCommand)"; purpose = 'main application' })
}
# UP TO TWO TEST ROUNDS. The first runs the plan's method. When the judgement asks to test ANOTHER method before
# building (usually the previous package's method, once the files it needs exist - MSIs caught while the vendor EXE ran,
# or extracted), the machine is already clean from the uninstall test, and the second round runs those lines with the
# same patience, then is judged and uninstall-tested the same way. The package is built from the round the AI chooses.
# THE RECORDING COVERS THE PLAN'S OWN ATTEMPTS AND NOTHING MORE. Left running through retries and AI waits it grew to
# gigabytes (about 30 MB a second) and its export held the whole evaluation.
$traceHolder = @{ stopped = $null }
$endTrace = { if ($trace -and $trace.ok -and -not $traceHolder.stopped) { $box.Progress = 'stopping the process recorder'; [void](Stop-AgentProcessTrace); $traceHolder.stopped = $trace } }
$pass = 1; $nextSteps = @()
while ($true) {
$allAttempts = New-Object System.Collections.Generic.List[object]
$trial = $null
# SEVERAL STEPS IN THE PLAN: there is nothing to discover - run them in that order, each one proven before the next.
# Trial and error is for a single installer whose line is not yet proven.
$seq = if ($pass -gt 1) { @($nextSteps) } else { @(Get-AgentList $p.Sequence) }
if (@($seq).Count -ge 2 -or $pass -gt 1) {
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "$(if ($pass -gt 1) { 'Second test round, another method' } else { 'The plan has' }): $(@($seq).Count) install step(s) - running them in that order, each one checked before the next."
    foreach ($st in @($seq | Sort-Object { [int]"$($_.order)" })) {
        Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "step $($st.order): $($st.installer) [$($st.purpose)]$(if ("$($st.source)".Trim()) { " - $($st.source)" })" -Command $(if ("$($st.commandLine)".Trim()) { "$($st.commandLine)" } else { "$($st.installer) $($st.arguments)" })
    }
    $trial = Invoke-AgentInstallSequence -Steps $seq -SourceFolder "$($sheet.folder)" -RunAs $p.RunAs -AlsoLookIn $look -Progress { param($t) $box.Progress = "$t" } -Judge $judge -CaptureMsiTo "$($sheet.capturedDir)"
    & $endTrace
    foreach ($st in @($trial.steps)) {
        & $showRan $st "Step $($st.order) $($st.installer)"
        & $showLooks $st
    }
    if (-not $trial.found) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "The sequence stopped after $($trial.completed) of $($trial.stepCount) steps - analysing what it left behind." }
    $allAttempts = New-Object System.Collections.Generic.List[object]
    foreach ($st in @($trial.steps)) { [void]$allAttempts.Add($st) }
}
# (the sequence above, when there was one, already WAS the trial. This used to read "-not $trial", which is also true of
# a single-installer trial after its FIRST round - so the retry candidates the AI worked out were never run, and a
# decision later described a response-file install that had never happened.)
$ranSequence = [bool]$trial
for ($round = 1; $round -le 3 -and -not $ranSequence; $round++) {
    $trial = Invoke-AgentSilentTrial -Installer $a.installer -Candidates $cands -RunAs $p.RunAs -AlsoLookIn $look -Progress { param($t) $box.Progress = "$t" } -Judge $judge -CaptureMsiTo "$($sheet.capturedDir)" `
                 -BetweenAttempts { & $cleanup 'before the next attempt' } -CleanBeforeFirst:($round -gt 1)
    & $endTrace
    foreach ($att in @($trial.attempts)) {
        $att.round = $round
        [void]$allAttempts.Add($att)
        & $showRan $att "Candidate $($att.candidate)"
        & $showLooks $att
    }
    if ($trial.found -or $round -eq 3) { break }
    # ask the AI what went wrong rather than shrugging and moving on
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Nothing installed silently - asking the AI what the failures mean.'
    $box.Progress = 'model: working out why the installs failed'
    $advice = Invoke-AgentRetryCandidates -Sheet $sheet -Attempts $allAttempts.ToArray() -Installer $a.installer -Progress { param($m) $box.Progress = $m }
    if (-not $advice) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text 'The AI could not be reached for advice - stopping the trial.'; break }
    Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "$($advice.diagnosis)"
    $sheet.retryAdvice = $advice
    if ($advice.needsSomethingElse -and $advice.needsSomethingElse.required) {
        # A PERSON HAS TO DO SOMETHING FIRST (record a response file, supply a licence). Running lines that need a file
        # nobody has made yet only produces failures that look like evidence - stop here and ask.
        Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Kind 'error' -Text "This installer needs more than a switch: $($advice.needsSomethingElse.what). $($advice.needsSomethingElse.how)"
        $sheet.humanNeededAfterTrial = $advice.needsSomethingElse
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text 'Stopping the trial here - nothing more can be proven until that is done. Whatever is on this machine now was NOT installed by a proven silent line.'
        break
    }
    $cands = @(@(Get-AgentList $advice.candidates) | ForEach-Object { @{ command = "$($_.command)"; source = "$($_.source)" } })
    if ($advice.giveUp -or -not $cands.Count) { Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Kind 'error' -Text "No sourced command left to try. $($advice.summary)"; break }
    Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "Trying $($cands.Count) different command(s): $(($cands | ForEach-Object { $_.command }) -join '  |  ')"
    $sheet.retryAdvice = $advice
}
$trial.attempts = $allAttempts.ToArray()
$sheet.trial = $trial
$sheet.provenSteps = @(& $mkProven $trial)
if (-not $trial.found) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text 'Still nothing installed silently - analysing what the last attempt left behind anyway.' }
# MSIs CAUGHT WHILE THE INSTALLER RAN - identified, so the AI can compare them with the previous package's method
$caught = @{}; foreach ($x in @(Get-AgentList $sheet.msiCaptured)) { if ($x) { $caught["$($x.file)".ToLowerInvariant()] = $x } }
foreach ($att in @($trial.attempts)) {
    foreach ($mc in @(@($att.msiCaptured) | Where-Object { $_ -and "$($_.path)".Trim() -and (Test-Path -LiteralPath "$($_.path)") })) {
        $rec = Get-AgentMsiCandidateRecord -Path "$($mc.path)" -ExpectedName "$($sheet.identity.app)" -ExpectedVersion "$($sheet.identity.version)" -ExpectedVendor "$($sheet.identity.vendor)" -HowObtained "caught at $($mc.unpackedAt) while '$($att.installer) $($att.arguments)' ran"
        $caught["$($rec.file)".ToLowerInvariant()] = $rec
    }
}
$sheet.msiCaptured = @($caught.Values)
if (@($sheet.msiCaptured).Count) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "The installer unpacked $(@($sheet.msiCaptured).Count) MSI(s) while it ran, now kept for comparison: $((@($sheet.msiCaptured) | ForEach-Object { "$($_.file) ('$($_.productName)' $($_.productVersion)$(if ($_.readable -and -not $_.selfContained) { ', needs its cabinets' }))" }) -join ', ')" }
# did the installer drop an MSI of its own while it ran? This is the trustworthy answer to "is there an MSI inside",
# and it costs nothing - the install already happened.
# Stop the recording before anything else looks at the machine, and get the child command lines out of it.
if ($trace -and $trace.ok) {
    & $endTrace
    $box.Progress = 'reading the child processes out of the recording'
    $traceStopped = $traceHolder.stopped; $trace = $null   # one recording, for the first round only
    $tf = Get-AgentProcessTraceFacts -BackingFile $traceStopped.backingFile
    $sheet.installTrace = $tf
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Recorded what the installer actually did while it ran. $($tf.note)"
    foreach ($cc in @(@($tf.msiCommands) | Select-Object -First 5)) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "   it ran: $("$($cc.detail)".Substring(0, [Math]::Min(160, "$($cc.detail)".Length)))"
    }
    if (@($tf.msiCommands).Count) { Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "Those are the vendor's own command lines - better evidence than any switch we guessed at." }
}
$msiNew = @(Get-AgentMsiAppearedDuringInstall -Baseline $msiBase)
$sheet.msiAppeared = $msiNew
if (@($msiNew).Count) {
    $real = @($msiNew | Where-Object { -not $_.isWindowsInstallerCacheCopy })
    foreach ($m in @($msiNew | Select-Object -First 8)) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' `
            -Text ("MSI appeared while installing: $($m.name)  [$($m.productName) $($m.productVersion) by $($m.manufacturer)]  $($m.sizeMB) MB$(if ($m.isWindowsInstallerCacheCopy) { '  (Windows cache copy, not the vendor file)' })")
    }
    if (@($real).Count) { Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "This EXE unpacks $(@($real).Count) MSI(s). Packaging one of them may be better than wrapping the EXE - but only if its product name and version match this application." }
}
$box.Progress = 'after snapshot + diff'
Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Taking the after snapshot and diffing the machine.'
$res = & ([scriptblock]::Create($a.analyze)) @{ before = $before; vendor = "$($sheet.identity.vendor)"; app = "$($sheet.identity.app)"; autostartBefore = $autoBase } $box
if ($res.Settings) {
    $st = $res.Settings
    Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Read back the settings this install wrote, so the package can decide what to change. $($st.note)"
    foreach ($svc in @(@($st.autostart.services) + @($st.autostart.tasks) + @($st.autostart.logon) | Select-Object -First 6)) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "   it added $($svc.entry), currently $($svc.enabled)$(if ("$($svc.company)".Trim()) { " - $($svc.company)" })"
    }
}

# START IT ONCE, when the AI asked for it. The prompts a user actually sees - "send us your usage data", the marketing
# sign-up, the first-run wizard - are written per user by the APPLICATION, after install. No install switch reaches
# them and the install snapshot cannot see them; starting the application once is the only way to find where each one
# keeps its state. Only for applications a person opens, and only on request.
$wantFirstRun = [bool]($pass -eq 1 -and $ev.inspectFirstRun.wanted -and "$($ev.inspectFirstRun.why)".Trim())
if ($wantFirstRun) {
    $launch = ''
    foreach ($sc in @(Get-AgentList $res.Shortcuts)) {
        $cand = "$(if ($sc.Target) { $sc.Target } elseif ($sc.Path) { $sc.Path } else { $sc })"
        if ($cand -and (Test-Path -LiteralPath $cand)) { $launch = $cand; break }
    }
    Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "Starting the application once, because $($ev.inspectFirstRun.why)"
    if (-not $launch) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'No shortcut appeared that could be started - the per-user prompts stay unverified, and the AI is told so.'
        $sheet.firstRun = @{ ok = $false; note = 'the install created no shortcut that could be started, so nothing about the first-run prompts was observed' }
    } else {
        $box.Progress = "starting $(Split-Path -Leaf $launch) once to see what it writes"
        $sheet.firstRun = Get-AgentFirstRunDelta -LaunchPath $launch
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "Started the application once to see what it writes for a user. $($sheet.firstRun.note)"
        foreach ($sl in @(@($sheet.firstRun.settingLike) | Select-Object -First 6)) {
            Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "   it remembered $($sl.name) = $($sl.value)   (in $($sl.key))"
        }
    }
}
$w = $trial.winner
$run = if ($w) { @{ Installer = $p.Installer; Args = "$($w.arguments)"; RunAs = "$($w.runAs)"; ExitCode = $w.exitCode; DurationSec = $w.durationSec; WindowsSeen = @($w.windowsSeen); TimedOut = [bool]$w.timedOut; Error = "$($w.error)"; Command = "$($w.command)" } }
       else { @{ Installer = $p.Installer; Args = ''; RunAs = "$($p.RunAs)"; ExitCode = $null; DurationSec = 0; WindowsSeen = @(); TimedOut = $false; Error = 'no candidate installed silently'; Command = '' } }
$run.Trial = @(@($trial.attempts) | ForEach-Object { "$($_.candidate). '$($_.arguments)' -> $($_.verdict)" })
Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text 'Classifying what the installer did.'
$box.Progress = 'model: classifying the snapshot'
$sheet = Invoke-AgentSnapshotDecision -Sheet $sheet -Result $res -RunInfo $run -Progress { param($m) $box.Progress = $m }
# The previous version was already removed BEFORE the new one went on - doing it here would be wrong and dangerous:
# by now the new version is what is installed, and the old package's uninstall would take THAT off instead.

# THE UNINSTALL IS TESTED TOO - the line the package will use, watched the same way, then the machine compared with how
# it was before the install. It also gives the machine back.
$dec = $sheet.decision
$installed = [bool]($trial.found -or ($dec -is [System.Collections.IDictionary] -and $dec.installOutcome -and [bool]$dec.installOutcome.installedAsExpected))
if ($dec -is [System.Collections.IDictionary] -and -not $dec.Contains('error') -and $installed) {
    $uc = @("$($dec.uninstall.testCommand)", "$($dec.uninstall.command)", "$(if ($res.Un) { $res.Un.QuietUninstall })") | Where-Object { "$_".Trim() } | Select-Object -First 1
    if ($uc) {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Now testing the uninstall the package will use - watched the same way, then the machine is compared with how it was before the install.' -Command "$uc"
        $box.Progress = 'uninstall test'
        $ut = Invoke-AgentUninstallTest -Sheet $sheet -Command "$uc" -Before $before -Judge $judge -Progress { param($t) $box.Progress = "$t" }
        $sheet.uninstallTest = $ut
        $ue = if ($null -ne $ut.exitCode) { " (exit $($ut.exitCode))" } elseif ("$($ut.note)".Trim()) { " - $($ut.note)" } else { '' }
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind $(if ($ut.verdict -in 'silent', 'progress') { 'step' } else { 'error' }) -Text "Uninstall: $($ut.verdict)$ue$(if ($ut.durationSec) { " after $($ut.durationSec)s" })" -Command "$($ut.command)"
        & $showLooks $ut
        if ($ut.leftBehind) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind $(if ([int]$ut.leftBehind.count) { 'error' } else { 'info' }) -Text "After the uninstall: $($ut.leftBehind.note)$(if ([int]$ut.leftBehind.count) { " - $([int]$ut.leftBehind.count) item(s)" })" }
        if ($ut.ran) {
            $box.Progress = 'model: judging the uninstall'
            $sheet = Invoke-AgentUninstallReview -Sheet $sheet -Progress { param($m) $box.Progress = $m }
            $rv = $sheet.uninstallReview
            if ($rv -and -not $rv.error) { Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "$(if ("$($rv.narration)".Trim()) { $rv.narration } else { $rv.summary })" }
        }
        [void](Save-AgentSheet -Sheet $sheet)
    } else {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text 'The uninstall could not be tested: the judgement named no uninstall command and the ARP entry has no QuietUninstallString. The application is still installed on this machine.'
    }
}

# WHATEVER HAPPENED IN THIS ROUND, THE MACHINE GOES BACK TO ITS BASELINE - for the next round, the next order, anyone
$roundCleanup = & $cleanup "at the end of test round $pass"
$dec = $sheet.decision
if ($pass -eq 1) {
    $tn = if ($dec -is [System.Collections.IDictionary]) { $dec.testNext } else { $null }
    if ($tn -is [System.Collections.IDictionary] -and [bool]$tn.wanted -and @(Get-AgentList $tn.steps).Count) {
        $programsLeft = @($roundCleanup.left.Programs).Count
        if ($programsLeft) {
            Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Kind 'error' -Text "The AI wants to test another method ($($tn.why)), but the first one could not be taken off this machine ($(@($roundCleanup.left.Programs) -join ', ')) - a second test on top of it would prove nothing. Not run; remove it by hand and re-run the evaluation."
        } else {
            if (-not $roundCleanup.clean) { Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "$([int]$roundCleanup.left.count) minor item(s) from the first method remain - the second round's diff is read with that in mind." }
            $sheet.firstMethod = [ordered]@{ trial = $sheet.trial; provenSteps = @($sheet.provenSteps); decision = $sheet.decision; uninstallTest = $sheet.uninstallTest; uninstallReview = $sheet.uninstallReview }
            $firstRes = $res; $firstRun = $run   # (the full snapshot result stays out of the saved sheet)
            $nextSteps = @(@(Get-AgentList $tn.steps) | ForEach-Object { $i = 0 } { $i++; [ordered]@{ order = $(if ($_.order) { [int]$_.order } else { $i }); installer = "$($_.installer)"; arguments = "$($_.arguments)"; commandLine = "$($_.commandLine)"; purpose = "$($_.purpose)" } })
            Add-AgentActivity -Log $log -Actor 'AI' -Stage 'evaluate' -Text "Before building, testing another method on this machine: $($tn.why)"
            $sheet.uninstallTest = $null; $sheet.uninstallReview = $null
            $pass = 2
            continue
        }
    }
} elseif ($sheet.firstMethod) {
    # TWO ROUNDS RAN: build from the one the AI chose. The first round's record is kept either way.
    $useRound = if ($dec -is [System.Collections.IDictionary] -and $dec.methodChoice) { [int]"$($dec.methodChoice.buildFromTestRound)" } else { 0 }
    if (-not $trial.found -or $useRound -eq 1) {
        $sheet.secondMethod = [ordered]@{ trial = $sheet.trial; provenSteps = @($sheet.provenSteps); uninstallTest = $sheet.uninstallTest; uninstallReview = $sheet.uninstallReview }
        $sheet.trial = $sheet.firstMethod.trial; $sheet.provenSteps = @($sheet.firstMethod.provenSteps)
        if ($sheet.firstMethod.uninstallTest) { $sheet.uninstallTest = $sheet.firstMethod.uninstallTest; $sheet.uninstallReview = $sheet.firstMethod.uninstallReview }
        $res = $firstRes; $run = $firstRun
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "The package is built from the FIRST test round's lines$(if (-not $trial.found) { ' - the second method did not install silently' } else { ' - the AI chose it' })."
    } else {
        Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text "The package is built from the SECOND test round's lines - the method the AI chose after testing both."
    }
    [void](Save-AgentSheet -Sheet $sheet)
}
break
}
return @{ sheet = $sheet; result = $res; run = $run }
'@ }
        default { return @'
param($a, $box)
$log = $a.activity; $script:AgentActivityLog = $log
$sheet = Invoke-AgentStage -Sheet $a.sheet -Id $a.id -With $a.with -Progress { param($m) $box.Progress = "$m"; Add-AgentActivity -Log $log -Actor $(if ("$m" -match '^model:') { 'AI' } else { 'TOOL' }) -Stage $a.id -Text "$m" }
return @{ sheet = $sheet }
'@ }
    }
}

function Show-AgentConsole {
    param([string]$Folder)
    Add-Type -AssemblyName PresentationFramework, System.Windows.Forms

    $ctx = @{ Sheet = $null; Folder = "$Folder"; Phase = 'idle'; Box = $null; Stage = ''; Result = $null; Run = $null
              Activity = (New-AgentActivityLog); Shown = 0; Auto = $true; Approved = @{}; Stop = $false }

    # published so a smoke driver can reach the live window and the log without a WPF Application object
    $script:LastConsoleContext = $ctx
    $script:LastConsoleLog = $ctx.Activity

    $win = New-Object Windows.Window
    $win.Title = 'Packaging Agent'; $win.WindowStartupLocation = 'CenterScreen'
    # The dark chrome, including the button styles. Without this WPF paints its own light-grey buttons,
    # which look wrong in a dark window - and FindResource('PbAccentButton') below silently falls back.
    $script:AgentWin = $win
    Set-AgentTheme $win
    $win.Background = '#181A1F'
    # Fit the SCREEN, never a hard-coded size: a 1180x820 window is taller than a 1366x768 laptop's work area, which
    # pushes the buttons off the bottom. Take what the desktop actually offers, minus a margin, and clamp to it.
    $wa = try { [Windows.SystemParameters]::WorkArea } catch { $null }
    $waW = if ($wa -and $wa.Width -gt 400) { [double]$wa.Width } else { 1280 }
    $waH = if ($wa -and $wa.Height -gt 300) { [double]$wa.Height } else { 800 }
    $win.Width = [Math]::Max(880, [Math]::Min(1180, $waW - 80))
    $win.Height = [Math]::Max(560, [Math]::Min(860, $waH - 60))
    $win.MinWidth = 760; $win.MinHeight = 480
    $win.MaxWidth = $waW; $win.MaxHeight = $waH
    if ($win.Width -ge $waW - 20 -or $win.Height -ge $waH - 20) { $win.WindowState = 'Maximized' }

    $g = New-Object Windows.Controls.Grid; $g.Margin = '16'
    foreach ($h in 'Auto', 'Auto', '*', 'Auto') { $r = New-Object Windows.Controls.RowDefinition; $r.Height = $h; [void]$g.RowDefinitions.Add($r) }

    # ---- row 0: the order + the one button ----------------------------------------------------------------------------
    $top = New-Object Windows.Controls.DockPanel; $top.LastChildFill = $true; $top.Margin = '0,0,0,10'
    $bRun = New-AgentButton -Glyph 'E768' -Text 'Run' -Accent -ToolTip 'Work the order: read it, let the AI plan it, test-install it on this machine (it asks first), build the package from our template, and let the AI check and finish it.'
    $bRun.MinWidth = 110
    $bKey = New-AgentButton -Glyph 'E192' -Text 'API key' -ToolTip 'Endpoint, model and credentials for this session.'
    $bBrowse = New-AgentButton -Glyph 'E8DA' -Text 'Browse' -ToolTip 'Pick the order folder.'
    $txtFolder = New-Object Windows.Controls.TextBox
    $txtFolder.Text = "$Folder"; $txtFolder.Background = '#12141A'; $txtFolder.Foreground = '#E7E9ED'; $txtFolder.BorderBrush = '#2A2F38'
    $txtFolder.Padding = '8,6'; $txtFolder.VerticalContentAlignment = 'Center'; $txtFolder.Margin = '0,0,8,0'; $txtFolder.FontSize = 12.5
    $txtFolder.MinWidth = 220; $txtFolder.TextWrapping = 'NoWrap'
    foreach ($b in @($bRun, $bKey, $bBrowse)) { [Windows.Controls.DockPanel]::SetDock($b, 'Right'); [void]$top.Children.Add($b) }
    [void]$top.Children.Add($txtFolder)
    [Windows.Controls.Grid]::SetRow($top, 0); [void]$g.Children.Add($top)

    # ---- row 1: THE CHANNEL --------------------------------------------------------------------------------------------
    # Three tiers, and the two links between them:
    #   AI        reasons and decides. It is not on this machine and can never touch it.
    #   AGENT     this tool. It executes what the AI asks for, watches what happens, and reports back. It decides nothing.
    #   ENDPOINT  this workstation. Where installers really run, and what the before/after picture is taken of.
    # Everything that happens crosses one of those two links. The strip shows which link is live, which way it is going
    # and what is in flight - so you can see who is busy without reading a word of the stream.
    $band = New-Object Windows.Controls.Border
    $band.Background = '#12141A'; $band.BorderBrush = '#242832'; $band.BorderThickness = '1'; $band.CornerRadius = '8'
    $band.Padding = '13,10'; $band.Margin = '0,0,0,10'
    $strip = New-Object Windows.Controls.Grid
    foreach ($cw in 'Auto', '*', 'Auto', '*', 'Auto') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $cw; [void]$strip.ColumnDefinitions.Add($cd) }
    $band.Child = $strip

    # THE THREE TIERS GET PICTURES, NOT LABELLED BOXES. Drawn from shapes rather than an icon font: the font attempt
    # rendered as empty rectangles on this very machine, and a picture that might not arrive is worse than no picture.
    # FLUENT MOTION, NOT WPF'S DEFAULTS. WPF ships CubicEase/QuadraticEase, which are not the curves Windows itself
    # uses - things animated with them read as slightly wrong, floaty at the start and abrupt at the end. Fluent is
    # specified as cubic beziers: standard (0.8,0,0.2,1) for something moving from A to B, decelerate (0,0,0,1) for
    # something arriving, accelerate (1,0,1,1) for something leaving. The only way to get those in WPF is a KeySpline.
    $Ease = @{ Standard = @(0.8, 0.0, 0.2, 1.0); Decelerate = @(0.0, 0.0, 0.0, 1.0); Accelerate = @(1.0, 0.0, 1.0, 1.0) }
    $mkMove = {
        param([double]$From, [double]$To, [int]$Ms, $Curve)
        $a = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $a.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds($Ms))
        [void]$a.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame $From, ([Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero))))
        $sp = New-Object Windows.Media.Animation.KeySpline
        $sp.ControlPoint1 = New-Object Windows.Point $Curve[0], $Curve[1]
        $sp.ControlPoint2 = New-Object Windows.Point $Curve[2], $Curve[3]
        [void]$a.KeyFrames.Add((New-Object Windows.Media.Animation.SplineDoubleKeyFrame $To, ([Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($Ms))), $sp))
        return $a
    }
    $mkPath = {
        param([string]$Data, $Stroke, $Fill, [double]$Thickness, [double]$Scale)
        $p = New-Object Windows.Shapes.Path
        $p.Data = [Windows.Media.Geometry]::Parse($Data)
        if ($Stroke) { $p.Stroke = $Stroke; $p.StrokeThickness = $Thickness; $p.StrokeLineJoin = 'Round'; $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round' }
        if ($Fill) { $p.Fill = $Fill }
        if ($Scale -ne 1) { $p.RenderTransform = (New-Object Windows.Media.ScaleTransform $Scale, $Scale) }
        return $p
    }
    # THE COURIER. Head and shoulders, drawn - the same person stands on the Agent plate and walks the links, so it
    # is obvious they are the same thing. Returns its parts so a transfer can tint them.
    $mkPerson = {
        param($Brush, [double]$Scale)
        $cv = New-Object Windows.Controls.Canvas
        $cv.Width = 16 * $Scale; $cv.Height = 17 * $Scale
        $h = New-Object Windows.Shapes.Ellipse
        $h.Width = 7 * $Scale; $h.Height = 7 * $Scale; $h.Fill = $Brush
        [Windows.Controls.Canvas]::SetLeft($h, 4.5 * $Scale); [Windows.Controls.Canvas]::SetTop($h, 0)
        [void]$cv.Children.Add($h)
        $s = & $mkPath 'M0,17 C0,11.4 3.6,8.8 8,8.8 C12.4,8.8 16,11.4 16,17 Z' $null $Brush 0 $Scale
        [void]$cv.Children.Add($s)
        return @{ Canvas = $cv; Head = $h; Torso = $s }
    }
    $mkIcon = {
        param([string]$Kind, [string]$Colour)
        $cv = New-Object Windows.Controls.Canvas
        $cv.Width = 24; $cv.Height = 23; $cv.VerticalAlignment = 'Center'; $cv.Margin = '0,0,9,0'
        $brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Colour))
        if ($Kind -eq 'brain') {
            # a brain: two lobes with a fissure down the middle and a fold in each half
            [void]$cv.Children.Add((& $mkPath 'M11,4.6 C10.2,3.3 8.3,3.3 7.6,4.7 C6.1,4.4 4.7,5.6 4.8,7.1 C3.5,7.6 2.9,9 3.5,10.2 C2.6,11.2 2.9,12.8 4,13.5 C4,15 5.3,16.1 6.8,15.9 C7.3,17.1 8.7,17.7 9.9,17.2 L9.9,20 L12.1,20 L12.1,17.2 C13.3,17.7 14.7,17.1 15.2,15.9 C16.7,16.1 18,15 18,13.5 C19.1,12.8 19.4,11.2 18.5,10.2 C19.1,9 18.5,7.6 17.2,7.1 C17.3,5.6 15.9,4.4 14.4,4.7 C13.7,3.3 11.8,3.3 11,4.6 Z' $brush $null 1.4 1))
            [void]$cv.Children.Add((& $mkPath 'M11,5.4 L11,17.6' $brush $null 1.1 1))
            [void]$cv.Children.Add((& $mkPath 'M7.8,7.6 C9.4,8.6 9.4,10.6 7.8,11.6' $brush $null 1.1 1))
            [void]$cv.Children.Add((& $mkPath 'M14.2,9.4 C12.6,10.4 12.6,12.4 14.2,13.4' $brush $null 1.1 1))
        } elseif ($Kind -eq 'person') {
            $ppl = & $mkPerson $brush 1.25
            [Windows.Controls.Canvas]::SetLeft($ppl.Canvas, 2); [Windows.Controls.Canvas]::SetTop($ppl.Canvas, 1)
            [void]$cv.Children.Add($ppl.Canvas)
        } else {
            # a workstation with something being installed into it - a bare screen says nothing about what happens here
            [void]$cv.Children.Add((& $mkPath 'M2.5,3 L21.5,3 L21.5,15.5 L2.5,15.5 Z' $brush $null 1.4 1))
            [void]$cv.Children.Add((& $mkPath 'M12,17 L12,19.5 M7,20.5 L17,20.5' $brush $null 1.4 1))
            [void]$cv.Children.Add((& $mkPath 'M12,5.8 L12,11.4 M9.2,8.8 L12,11.8 L14.8,8.8' $brush $null 1.4 1))
        }
        return $cv
    }
    # A tier plate: its picture, a status light, the name, and what that tier is for.
    $mkNode = {
        param([string]$Kind, [string]$Name, [string]$Sub, [string]$Colour)
        $b = New-Object Windows.Controls.Border
        $b.Background = '#1A1D23'; $b.BorderBrush = '#2A2F38'; $b.BorderThickness = '1'; $b.CornerRadius = '6'
        $b.Padding = '10,7'; $b.VerticalAlignment = 'Center'
        $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
        [void]$row.Children.Add((& $mkIcon $Kind $Colour))
        $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'
        $hdr = New-Object Windows.Controls.StackPanel; $hdr.Orientation = 'Horizontal'
        $led = New-Object Windows.Shapes.Ellipse
        $led.Width = 7; $led.Height = 7; $led.VerticalAlignment = 'Center'; $led.Margin = '0,0,6,0'; $led.Opacity = 0.3
        $led.Fill = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Colour)))
        [void]$hdr.Children.Add($led)
        $nm = New-Object Windows.Controls.TextBlock
        $nm.Text = $Name; $nm.Foreground = '#C8CDD4'; $nm.FontSize = 12.5; $nm.FontWeight = 'SemiBold'; $nm.VerticalAlignment = 'Center'
        [void]$hdr.Children.Add($nm)
        [void]$sp.Children.Add($hdr)
        $sb = New-Object Windows.Controls.TextBlock
        $sb.Text = $Sub; $sb.Foreground = '#5A616B'; $sb.FontSize = 10; $sb.Margin = '13,1,0,0'
        [void]$sp.Children.Add($sb)
        [void]$row.Children.Add($sp)
        $b.Child = $row
        return @{ Plate = $b; Led = $led; Colour = $Colour }
    }
    # A link: a hairline, and THE MESSAGE travelling it. The tiers stay put - the agent lives on this workstation and
    # goes nowhere. What moves between them is what was said: an instruction down, evidence back up.
    $mkLink = {
        $cv = New-Object Windows.Controls.Canvas
        $cv.Height = 34; $cv.Margin = '10,0'; $cv.ClipToBounds = $true; $cv.VerticalAlignment = 'Center'
        $ln = New-Object Windows.Shapes.Line
        $ln.X1 = 0; $ln.X2 = 40; $ln.Y1 = 26; $ln.Y2 = 26; $ln.StrokeThickness = 1
        $ln.Stroke = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#2A3A40')))
        [void]$cv.Children.Add($ln)
        $msg = New-Object Windows.Controls.Border
        $msg.Background = '#10252B'; $msg.BorderThickness = '1'; $msg.CornerRadius = '9'; $msg.Padding = '8,2'
        $msg.BorderBrush = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#2A3A40')))
        $msg.Visibility = 'Hidden'
        $inner = New-Object Windows.Controls.StackPanel; $inner.Orientation = 'Horizontal'
        # a small chevron in the nose of the message, pointing the way it is going
        $arw = & $mkPath 'M0,0 L4,4 L0,8' (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#3FC9DE'))) $null 1.4 1
        $arw.VerticalAlignment = 'Center'; $arw.Margin = '0,0,6,0'; $arw.RenderTransformOrigin = '0.5,0.5'
        [void]$inner.Children.Add($arw)
        $tx = New-Object Windows.Controls.TextBlock
        $tx.FontSize = 10.5; $tx.Foreground = '#3FC9DE'; $tx.MaxWidth = 210; $tx.TextTrimming = 'CharacterEllipsis'
        $tx.VerticalAlignment = 'Center'
        [void]$inner.Children.Add($tx)
        $msg.Child = $inner
        [Windows.Controls.Canvas]::SetTop($msg, 3); [Windows.Controls.Canvas]::SetLeft($msg, 0)
        [void]$cv.Children.Add($msg)
        # A Canvas in a Grid star column DOES get a real width - unlike one inside a StackPanel, which gets infinity.
        $cv.add_SizeChanged({ $ln.X2 = $cv.ActualWidth }.GetNewClosure())
        return @{ Track = $cv; Line = $ln; Msg = $msg; Arrow = $arw; Label = $tx }
    }
    $nAi = & $mkNode 'brain'  'AI'       'reasons, decides'   '#C58AF9'
    $nAg = & $mkNode 'person' 'Agent'    'executes, observes' '#3FC9DE'
    $nEp = & $mkNode 'screen' 'Endpoint' 'this workstation'   '#5BA97A'
    $lkAi = & $mkLink      # AI    <-> Agent
    $lkEp = & $mkLink      # Agent <-> Endpoint
    $col = 0
    foreach ($el in @($nAi.Plate, $lkAi.Track, $nAg.Plate, $lkEp.Track, $nEp.Plate)) {
        [Windows.Controls.Grid]::SetColumn($el, $col); [void]$strip.Children.Add($el); $col++
    }
    [Windows.Controls.Grid]::SetRow($band, 1); [void]$g.Children.Add($band)

    # The status light on a tier: steady and dim when it is idle, breathing while it is the one doing the work.
    $ledPulse = {
        param($Node, $Busy)
        $Node.Led.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
        if ($Busy) {
            $an = New-Object Windows.Media.Animation.DoubleAnimation
            $an.From = 1.0; $an.To = 0.2; $an.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(800))
            $an.AutoReverse = $true; $an.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
            $Node.Led.BeginAnimation([Windows.UIElement]::OpacityProperty, $an)
        } else { $Node.Led.Opacity = 0.3 }
    }

    # ONE TRANSFER, SHOWN ON THE LINK IT REALLY CROSSED. Called from the activity stream, so the strip can only ever
    # show something that actually happened - never a decoration running on its own timer.
    #   toAgent     the AI has decided something and handed it down
    #   toAi        evidence going back up for the AI to reason about
    #   onEndpoint  the agent is doing something to this workstation
    #   toYou       it needs the packager, and stops
    $ctx.ChannelAt = ''
    $channel = {
        param([string]$Leg, [string]$Label)
        $link = if ($Leg -eq 'onEndpoint') { $lkEp } else { $lkAi }
        $tint = switch ($Leg) { 'toAi' { '#C58AF9' } 'onEndpoint' { '#5BA97A' } 'toYou' { '#E0BE7C' } default { '#3FC9DE' } }
        $brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($tint))
        # only one link is ever live, so the other goes quiet rather than leaving a stale message sitting on it
        foreach ($l in @($lkAi, $lkEp)) { if ($l -ne $link) { $l.Msg.Visibility = 'Hidden' } }
        $link.Label.Text = "$Label"; $link.Label.Foreground = $brush
        $link.Msg.BorderBrush = $brush; $link.Arrow.Stroke = $brush
        $link.Msg.Visibility = $(if ("$Label".Trim()) { 'Visible' } else { 'Hidden' })
        # the chevron points the way this message is actually going
        $link.Arrow.RenderTransform = (New-Object Windows.Media.ScaleTransform $(if ($Leg -eq 'toAi') { -1 } else { 1 }), 1)
        $w = [double]$link.Track.ActualWidth; if ([double]::IsNaN($w) -or $w -lt 60) { $w = 200 }
        # Keep the message inside its own track. The label is capped to the room available BEFORE measuring, so a long
        # line shortens the pill instead of pushing it off the end - the first version slid it under the next tier.
        $link.Label.MaxWidth = [Math]::Max(60, $w - 64)
        # A real layout pass, then the real width. DesiredSize alone came back stale on a pill that was already on
        # screen, so the message was sent past the end of its own track and clipped against the next tier.
        $link.Msg.InvalidateMeasure(); $link.Track.UpdateLayout()
        $mw = [double]$link.Msg.ActualWidth
        if ([double]::IsNaN($mw) -or $mw -lt 10) { $mw = [double]$link.Msg.DesiredSize.Width }
        if ([double]::IsNaN($mw) -or $mw -lt 10) { $mw = 90 }
        $far = [Math]::Max(0, $w - $mw)
        $to = switch ($Leg) { 'toAi' { 0 } 'toYou' { $far / 2 } default { $far } }
        $from = switch ($Leg) { 'toAi' { $far } 'toYou' { $far / 2 } default { 0 } }
        $link.Msg.BeginAnimation([Windows.Controls.Canvas]::LeftProperty, (& $mkMove $from $to 320 $Ease.Standard))
        $link.Msg.BeginAnimation([Windows.UIElement]::OpacityProperty, (& $mkMove 0 1 150 $Ease.Decelerate))
        & $ledPulse $nAi ($Leg -eq 'toAi')
        & $ledPulse $nAg ($Leg -eq 'toAgent' -or $Leg -eq 'toYou')
        & $ledPulse $nEp ($Leg -eq 'onEndpoint')
        $ctx.ChannelAt = "$Leg"
    }

    # ---- row 2: WHERE IT IS  |  WHAT IS HAPPENING  |  WHAT IS ESTABLISHED ------------------------------------------------
    # Three narrow jobs rather than one wide one. The stream keeps the width because it carries the detail; the two
    # side panels are deliberately thin and are kept thin - one line per fact, trimmed, with the full text on hover.
    # Anything that will not fit in a line belongs in the stream or the report, not here.
    $mid = New-Object Windows.Controls.Grid
    foreach ($cw in '170', '*', '198') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $cw; [void]$mid.ColumnDefinitions.Add($cd) }

    $mkPanel = {
        param([string]$Title, [string]$Margin)
        $b = New-Object Windows.Controls.Border
        $b.Background = '#15171C'; $b.BorderBrush = '#2A2F38'; $b.BorderThickness = '1'; $b.CornerRadius = '6'
        $b.Padding = '10,9'; $b.Margin = $Margin
        $dp = New-Object Windows.Controls.DockPanel; $dp.LastChildFill = $true
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = $Title; $t.Foreground = '#5A616B'; $t.FontSize = 10; $t.Margin = '0,0,0,8'
        [Windows.Controls.DockPanel]::SetDock($t, 'Top'); [void]$dp.Children.Add($t)
        $s = New-Object Windows.Controls.ScrollViewer
        $s.VerticalScrollBarVisibility = 'Auto'; $s.HorizontalScrollBarVisibility = 'Disabled'
        $p = New-Object Windows.Controls.StackPanel
        $s.Content = $p; [void]$dp.Children.Add($s)
        $b.Child = $dp
        return @{ Box = $b; Panel = $p }
    }
    $railP = & $mkPanel 'Run' '0,0,9,0'
    $chips = $railP.Panel
    [Windows.Controls.Grid]::SetColumn($railP.Box, 0); [void]$mid.Children.Add($railP.Box)

    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.HorizontalScrollBarVisibility = 'Disabled'
    $sv.Background = '#15171C'; $sv.Padding = '12'; $sv.BorderBrush = '#2A2F38'; $sv.BorderThickness = '1'
    $feed = New-Object Windows.Controls.StackPanel
    $sv.Content = $feed
    [Windows.Controls.Grid]::SetColumn($sv, 1); [void]$mid.Children.Add($sv)

    $evP = & $mkPanel 'Established' '9,0,0,0'
    $evidence = $evP.Panel
    [Windows.Controls.Grid]::SetColumn($evP.Box, 2); [void]$mid.Children.Add($evP.Box)

    [Windows.Controls.Grid]::SetRow($mid, 2); [void]$g.Children.Add($mid)

    # ---- row 3: status + the few things you may want afterwards -----------------------------------------------------------
    $bottom = New-Object Windows.Controls.DockPanel; $bottom.LastChildFill = $true; $bottom.Margin = '0,10,0,0'
    $bClose = New-Object Windows.Controls.Button; $bClose.Content = 'Close'; $bClose.Padding = '16,5'; $bClose.IsCancel = $true
    $bReport = New-AgentButton -Glyph 'E8A5' -Text 'Report' -ToolTip 'The evaluation sheet, with the full AI/tool conversation.'; $bReport.IsEnabled = $false
    $bPkg = New-AgentButton -Glyph 'E8DA' -Text 'Package folder' -ToolTip 'Open the package the tool built.'; $bPkg.IsEnabled = $false
    $pbar = New-Object Windows.Controls.ProgressBar
    $pbar.Height = 3; $pbar.IsIndeterminate = $true; $pbar.Visibility = 'Collapsed'; $pbar.BorderThickness = '0'
    $pbar.Foreground = '#2BA6B8'; $pbar.Background = '#2A2E36'; $pbar.Margin = '0,0,0,6'
    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Foreground = '#B7BEC8'; $lbl.FontSize = 12; $lbl.VerticalAlignment = 'Center'
    # one line, trimmed - a wrapping status line grows the bottom row and eats the feed
    $lbl.TextWrapping = 'NoWrap'; $lbl.TextTrimming = 'CharacterEllipsis'
    foreach ($b in @($bClose, $bPkg, $bReport)) { [Windows.Controls.DockPanel]::SetDock($b, 'Right'); [void]$bottom.Children.Add($b) }
    [void]$bottom.Children.Add($lbl)
    # ---- TALK TO IT WHILE IT WORKS --------------------------------------------------------------------------------
    # Until now the packager could only answer when the agent happened to ask. Watching it go the wrong way - the
    # wrong predecessor, a template placeholder being treated as a defect, a verify loop going nowhere - and having
    # no way to say so except killing the window is the worst part of using this. Whatever is typed here reaches the
    # AI on its next round, and is taken as fact about this order.
    $chatRow = New-Object Windows.Controls.DockPanel; $chatRow.LastChildFill = $true; $chatRow.Margin = '0,8,0,0'
    $bSend = New-AgentButton -Glyph 'E724' -Text 'Send' -ToolTip 'Tell the AI this now - it reaches it on the next round.' -Margin '8,0,0,0'
    [Windows.Controls.DockPanel]::SetDock($bSend, 'Right'); [void]$chatRow.Children.Add($bSend)
    $txtChat = New-Object Windows.Controls.TextBox
    $txtChat.Height = 30; $txtChat.VerticalContentAlignment = 'Center'; $txtChat.FontSize = 12.5
    $txtChat.Background = '#12141A'; $txtChat.Foreground = '#E7E9ED'; $txtChat.BorderBrush = '#2A2F38'
    $txtChat.Tag = 'Tell the AI something - a correction, an answer, or just stop and look at this'
    $txtChat.Text = "$($txtChat.Tag)"; $txtChat.Foreground = '#5A616B'
    [void]$chatRow.Children.Add($txtChat)

    $sendChat = {
        $t = "$($txtChat.Text)".Trim()
        if (-not $t -or $t -eq "$($txtChat.Tag)") { return }
        $txtChat.Text = ''
        & $say 'YOU' $ctx.Stage $t 'step'
        if ($ctx.Phase -eq 'running') {
            # a stage is working: it drains this on its next round, which is the whole point of the queue
            try { [void](Get-AgentHumanInbox).Add($t) } catch { & $say 'TOOL' $ctx.Stage "Could not pass that along: $($_.Exception.Message)" 'error' }
            return
        }
        # NOTHING IS RUNNING, SO NOTHING WOULD EVER READ IT. Queueing here is how a message typed after a failure sat
        # unread while the window claimed the next step would see it. Wake it instead and let it answer.
        if (-not $ctx.Sheet) { & $say 'TOOL' '' 'There is no order open yet - press Run first, then tell me anything you need to.' 'step'; return }
        if ($ctx.Consulting) { try { [void](Get-AgentHumanInbox).Add($t) } catch {}; return }
        & $askAgent $t
    }

    # Ask the AI directly, with the order's whole conversation behind it, and show what it says.
    $askAgent = {
        param($Message)
        $ctx.Consulting = $true
        $pbar.Visibility = 'Visible'
        & $channel 'toAi' 'the packager asked something'
        $arg = @{ sheet = $ctx.Sheet; activity = $ctx.Activity; message = "$Message" }
        $box = Start-AgentRunspace -Arg $arg -Script @'
param($a, $box)
$log = $a.activity; $script:AgentActivityLog = $log
$r = Invoke-AgentConsult -Sheet $a.sheet -Message "$($a.message)" -Progress { param($t) $box.Progress = "$t" }
@{ sheet = $a.sheet; result = $r }
'@
        # THE TIMER LIVES ON $ctx, NOT IN THIS FUNCTION. $askAgent returns immediately; its locals die with it, so a
        # handler that referred to a local $cTimer found $null and threw on .Stop() - which WPF reports against
        # ShowDialog, killing the whole window. $ctx outlives everything. (A closure would capture the local, but a
        # closure cannot see this session's FUNCTIONS, which is the problem it was introduced to solve.)
        $ctx.ConsultBox = $box; $ctx.ConsultStarted = Get-Date
        $cTimer = New-Object Windows.Threading.DispatcherTimer
        $ctx.ConsultTimer = $cTimer
        $cTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        # NO GetNewClosure HERE. A closure gets its own scope and the FUNCTIONS this handler needs -
        # Stop-AgentRunspace, Get-AgentStageDef - are not visible from it, so the completion branch threw, WPF
        # swallowed it, and the window sat with the work finished and nothing showing it. The whole body is wrapped
        # as well: a fault in here must never be able to leave the window waiting on something already done.
        $cTimer.add_Tick({
          try {
            if (-not $ctx.ConsultBox.Done) {
                if ("$($ctx.ConsultBox.Progress)".Trim()) { $pbar.ToolTip = "$($ctx.ConsultBox.Progress)" }
                $waited = try { ((Get-Date) - $ctx.ConsultStarted).TotalSeconds } catch { 0 }
                if ($waited -gt 900) {
                    $ctx.ConsultTimer.Stop(); $ctx.Consulting = $false; $pbar.Visibility = 'Collapsed'
                    try { Stop-AgentRunspace -Box $ctx.ConsultBox } catch {}
                    & $say 'TOOL' '' "No answer after $([int]$waited)s - I have stopped waiting. Your message is still on the record." 'error'
                }
                return
            }
            $ctx.ConsultTimer.Stop(); $ctx.Consulting = $false; $pbar.Visibility = 'Collapsed'
            $res = $ctx.ConsultBox.Result
            $err = "$($ctx.ConsultBox.Error)".Trim()
            try { Stop-AgentRunspace -Box $ctx.ConsultBox } catch {}
            if ($res -and $res.sheet) { $ctx.Sheet = $res.sheet }
            $r = if ($res) { $res.result } else { $null }
            if (-not $r) { & $say 'TOOL' '' "I could not answer that$(if ($err) { ": $err" }). Your message is on the record." 'error'; return }
            if ("$($r.reply)".Trim()) { & $say 'AI' 'consult' "$($r.reply)" 'step' }
            if ("$($r.whatYouWillDo)".Trim()) { & $say 'AI' 'consult' "What I will do: $($r.whatYouWillDo)" 'step' }
            if (@($r.whatYouChecked).Count) { & $say 'TOOL' 'consult' "It checked: $((@($r.whatYouChecked)) -join '; ')" 'step' }
            & $drawChips
            # IT WAS ASKED WHETHER A QUIET STAGE IS STUCK, AND IT ANSWERED. Acting on that is the whole point of
            # having asked - a verdict nobody carries out is just commentary.
            if (("$($r.stopTheRunningStage)" -eq 'True' -or $r.stopTheRunningStage -eq $true) -and $ctx.Phase -eq 'running' -and $ctx.Box) {
                $stuck = "$($ctx.Stage)"
                & $say 'AI' $stuck "Stopping $stuck - $(if ("$($r.whyStopOrWait)".Trim()) { $r.whyStopOrWait } else { 'it is not going to finish' })." 'error'
                try { Stop-AgentRunspace -Box $ctx.Box } catch {}
                $ctx.Phase = 'idle'; $pbar.Visibility = 'Collapsed'
                [void](Set-AgentStage -Sheet $ctx.Sheet -Id $stuck -Status 'failed' -Note "the AI judged this stuck: $($r.whyStopOrWait)")
                & $drawChips
                & $troubleshootThen $stuck "the stage was stopped because it was stuck: $($r.whyStopOrWait)"
                return
            }
            if ("$($r.stopTheRunningStage)" -eq 'False' -and $ctx.Phase -eq 'running') {
                # it looked and said keep going - so reset the stall clock rather than asking again in a minute
                $ctx.LastProgressAt = Get-Date; $ctx.StallTold = 0
                & $say 'AI' "$($ctx.Stage)" "Leaving it running$(if ("$($r.whyStopOrWait)".Trim()) { " - $($r.whyStopOrWait)" })." 'step'
            }
            $redo = "$($r.redoStage)".Trim()
            if ($redo -and (Get-AgentStageDef -Id $redo)) {
                & $say 'AI' 'consult' "That means $((Get-AgentStageDef -Id $redo).Title) has to be done again$(if ("$($r.whyRedo)".Trim()) { " - $($r.whyRedo)" })." 'step'
                try { $ctx.Sheet.stages.Remove($redo) } catch {}
                $ctx.Approved.Remove($redo) | Out-Null
                & $drawChips; & $startStage $redo
            }
          } catch {
            $ctx.ConsultTimer.Stop(); $ctx.Consulting = $false; $pbar.Visibility = 'Collapsed'
            & $say 'TOOL' '' "Something went wrong showing you that answer: $($_.Exception.Message)" 'error'
          }
        })
        $cTimer.Start()
    }
    $bSend.add_Click({ & $sendChat })
    $txtChat.add_GotFocus({ if ("$($txtChat.Text)" -eq "$($txtChat.Tag)") { $txtChat.Text = ''; $txtChat.Foreground = '#E7E9ED' } })
    $txtChat.add_LostFocus({ if (-not "$($txtChat.Text)".Trim()) { $txtChat.Text = "$($txtChat.Tag)"; $txtChat.Foreground = '#5A616B' } })
    $txtChat.add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { & $sendChat; $e.Handled = $true } })

    $bottomWrap = New-Object Windows.Controls.StackPanel
    [void]$bottomWrap.Children.Add($pbar); [void]$bottomWrap.Children.Add($chatRow); [void]$bottomWrap.Children.Add($bottom)
    [Windows.Controls.Grid]::SetRow($bottomWrap, 3); [void]$g.Children.Add($bottomWrap)
    $win.Content = $g

    $lbl.Text = if (Test-AgentHasKey) { "Ready. Key: $(Get-AgentKeySource) · model $(Get-AgentModel)" } else { 'No API key yet - click API key, or press Run to be asked.' }

    # ---- helpers (plain scriptblocks: a closure cannot see this script's functions) ---------------------------------------
    # THE FLOW, SHOWN AS IT HAPPENS.
    # The packager should be able to glance at this and know where the agent is, the way you can glance at somebody
    # working. Five phases across the top - Understand, Evaluate, Create, Verify, Handover - each with the stages
    # inside it, and Troubleshoot appearing only when something has gone wrong, because that is when it exists.
    # The phase being worked on carries a live dot; everything else is quiet. No animation for its own sake.
    $phaseOrder = @('Understand', 'Evaluate', 'Create', 'Verify', 'Handover')
    $drawChips = {
        $chips.Children.Clear()
        $byPhase = @{}
        $flow = @()
        $activePhase = ''
        if ($ctx.Sheet) {
            $flow = @(Get-AgentFlow -Sheet $ctx.Sheet)
            foreach ($s in $flow) {
                $ph = "$((Get-AgentStageDef -Id $s.id).Phase)"; if (-not $ph) { $ph = 'Other' }
                if (-not $byPhase.ContainsKey($ph)) { $byPhase[$ph] = @() }
                $byPhase[$ph] += $s
            }
            # only when a stage is actually running - Get-AgentStageDef's -Id is mandatory, so between stages (and
            # right after a fresh start, when Stage is empty) this threw a binding error out of the timer tick
            $activePhase = if ("$($ctx.Stage)".Trim()) { "$((Get-AgentStageDef -Id $ctx.Stage).Phase)" } else { '' }
        } else {
            # Before a run there is nothing to report yet, but the route is still worth showing: the packager
            # can see where this is going before committing to it. All five quiet, no dot, no counts.
            foreach ($ph in $phaseOrder) { $byPhase[$ph] = @() }
        }
        $row = New-Object Windows.Controls.StackPanel
        $n = 0
        foreach ($ph in $phaseOrder) {
            if (-not $byPhase.ContainsKey($ph)) { continue }
            $n++
            $stages = @($byPhase[$ph])
            $states = @($stages | ForEach-Object { "$($_.state)" })
            # one phase is only as finished as its least finished stage
            $phState = if ($stages.Count -eq 0) { 'todo' }   # no stages yet: nothing is finished, whatever the list says
                       elseif ($states -contains 'failed') { 'failed' }
                       elseif ($ph -eq $activePhase -and $ctx.Phase -eq 'running') { 'running' }
                       elseif ($states -contains 'waiting') { 'waiting' }
                       elseif (@($states | Where-Object { $_ -notin 'done', 'skipped' }).Count -eq 0) { 'done' }
                       elseif ($states -contains 'blocked' -and @($states | Where-Object { $_ -eq 'ready' }).Count -eq 0) { 'blocked' }
                       else { 'todo' }
            $fg = switch ($phState) { 'done' { '#6A9955' } 'failed' { '#F48771' } 'running' { '#3FC9DE' } 'waiting' { '#E0BE7C' } 'blocked' { '#5A616B' } default { '#8A93A0' } }
            $bd = New-Object Windows.Controls.Border
            $bd.BorderBrush = $fg; $bd.BorderThickness = '2,0,0,0'; $bd.Padding = '8,3'; $bd.Margin = '0,0,0,9'
            if ($phState -eq 'running') { $bd.Background = '#10252B' }
            elseif ($phState -eq 'failed') { $bd.Background = '#2C1E1C' }
            $inner = New-Object Windows.Controls.StackPanel
            $hd = New-Object Windows.Controls.StackPanel; $hd.Orientation = 'Horizontal'
            # the live dot: only on the phase actually being worked, so the eye goes straight to it
            $dot = New-Object Windows.Shapes.Ellipse
            $dot.Width = 6; $dot.Height = 6; $dot.Margin = '0,0,6,0'; $dot.VerticalAlignment = 'Center'
            $dot.Fill = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($fg)))
            if ($phState -ne 'running') { $dot.Opacity = 0.45 }
            if ($phState -eq 'running') {
                $an = New-Object Windows.Media.Animation.DoubleAnimation
                $an.From = 1.0; $an.To = 0.25; $an.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(750))
                $an.AutoReverse = $true; $an.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
                $dot.BeginAnimation([Windows.UIElement]::OpacityProperty, $an)
            }
            [void]$hd.Children.Add($dot)
            $lbl = New-Object Windows.Controls.TextBlock
            $lbl.Text = $ph; $lbl.Foreground = $fg; $lbl.FontSize = 12; $lbl.FontWeight = $(if ($phState -eq 'running') { 'SemiBold' } else { 'Normal' })
            $lbl.VerticalAlignment = 'Center'
            [void]$hd.Children.Add($lbl)
            [void]$inner.Children.Add($hd)
            # THE STAGES INSIDE THE PHASE. There is a whole column of height here, so use it: the actual steps of the
            # flow, one short line each, with the state carried by the marker rather than by a word. A phase with no
            # stages yet (before a run) shows nothing underneath, which is honest - the route is known, the work isn't.
            foreach ($st in $stages) {
                # A DockPanel, not a StackPanel: a horizontal StackPanel hands its children infinite width, so
                # TextTrimming never fires and a long stage name is simply chopped off mid-letter.
                $sr = New-Object Windows.Controls.DockPanel; $sr.LastChildFill = $true; $sr.Margin = '12,3,0,0'
                $mk = New-Object Windows.Controls.TextBlock
                $mk.Text = $(switch ("$($st.state)") { 'done' { '✓' } 'skipped' { '–' } 'failed' { '!' } 'running' { '▸' } 'waiting' { '?' } default { '·' } })
                $mk.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($(switch ("$($st.state)") {
                    'done' { '#6A9955' } 'failed' { '#F48771' } 'running' { '#3FC9DE' } 'waiting' { '#E0BE7C' } default { '#4A5058' } }))))
                $mk.FontSize = 10.5; $mk.Width = 12; $mk.VerticalAlignment = 'Center'
                [Windows.Controls.DockPanel]::SetDock($mk, 'Left'); [void]$sr.Children.Add($mk)
                $sn = New-Object Windows.Controls.TextBlock
                # Wrap rather than trim. There is height to spare in this column and none to spare in a stage name -
                # "Test-install on this…" tells you less than the two lines it would have taken to say it.
                $sn.Text = "$($st.title)"; $sn.FontSize = 11; $sn.TextWrapping = 'Wrap'
                $sn.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($(
                    if ("$($st.state)" -eq 'running') { '#C8CDD4' } elseif ("$($st.state)" -in 'done', 'skipped') { '#7A828E' } else { '#5A616B' }))))
                $sn.ToolTip = "$($st.title): $($st.state)$(if ("$($st.why)".Trim()) { " - $($st.why)" })"
                [void]$sr.Children.Add($sn)
                [void]$inner.Children.Add($sr)
            }
            $bd.Child = $inner
            $bd.ToolTip = (@($stages | ForEach-Object { "$($_.title): $($_.state)$(if ("$($_.why)".Trim()) { " - $($_.why)" })" }) -join "`n")
            [void]$row.Children.Add($bd)
        }
        # Troubleshoot is not a phase of its own - it appears when something has gone wrong, and says so
        if ($ctx.Phase -eq 'troubleshoot' -or @($flow | Where-Object { $_.state -eq 'failed' }).Count) {
            $tb = New-Object Windows.Controls.Border
            $tb.Background = '#2C1E1C'; $tb.CornerRadius = '4'; $tb.Padding = '8,4'; $tb.Margin = '0,2,0,0'
            $tb.BorderBrush = '#F48771'; $tb.BorderThickness = '1'
            $tt = New-Object Windows.Controls.TextBlock
            $tt.Text = $(if ($ctx.Phase -eq 'troubleshoot') { 'Troubleshooting…' } else { 'Troubleshoot' })
            $tt.Foreground = '#F48771'; $tt.FontSize = 11
            $tb.Child = $tt
            $tb.ToolTip = 'Something failed. The agent looks at it before asking you.'
            [void]$row.Children.Add($tb)
        }
        [void]$chips.Children.Add($row)
        & $drawEvidence
    }
    # WHAT HAS ACTUALLY BEEN ESTABLISHED. Not a log and not a summary - the handful of facts a reviewer would ask
    # for, each on ONE line. A fact only appears once it is genuinely known, so an empty row never pretends.
    # Long values are trimmed and carry the whole thing on hover; this column is too narrow for anything else.
    $drawEvidence = {
        $evidence.Children.Clear()
        $rows = New-Object System.Collections.Generic.List[object]
        $add = {
            param([string]$Label, [string]$Value, [string]$Colour)
            if (-not "$Value".Trim()) { return }
            $rows.Add(@{ L = $Label; V = "$Value".Trim(); C = $(if ($Colour) { $Colour } else { '#C8CDD4' }) })
        }
        $s = $ctx.Sheet
        if ($s) {
            & $add 'Package'  "$($s.package)" ''
            & $add 'Order'    "$($s.ritm)" ''
            try {
                $rt = "$($s.plan.route.kind)"
                $rtTxt = switch ($rt) { 'reuse_as_is' { 'reuse, unchanged' } 'reuse_with_changes' { 'reuse, with changes' } 'fresh' { 'fresh package' } default { '' } }
                if ($rtTxt -and "$($s.plan.route.number)".Trim()) { $rtTxt = "$rtTxt · route $($s.plan.route.number)" }
                & $add 'Route' $rtTxt $(if ($rt -like 'reuse*') { '#6A9955' } else { '#C8CDD4' })
            } catch {}
            try {
                $p = $s.history.predecessor
                if ($p) { & $add 'Predecessor' "$(if ("$($p.name)".Trim()) { $p.name } else { Split-Path -Leaf "$($p.path)" })" '' }
                elseif ($s.history.predecessorSearched) { & $add 'Predecessor' 'none found' '#8A93A0' }
            } catch {}
            try {
                $inst = "$(@(Get-AgentList $s.plan.install.steps | ForEach-Object { "$($_.installer)" }) -join ' + ')"
                if (-not $inst.Trim()) { $inst = "$(@($s.sources.installers | ForEach-Object { "$($_.name)" }) | Select-Object -First 1)" }
                & $add 'Installer' $inst ''
            } catch {}
            try { & $add 'Built' "$(Split-Path -Leaf "$($s.stages.build.folder)")" '' } catch {}
            try {
                if ($s.PSObject.Properties.Name -contains 'verificationPassed' -or $s.Contains('verificationPassed')) {
                    & $add 'Verified' $(if ($s.verificationPassed) { 'yes' } else { 'not yet' }) $(if ($s.verificationPassed) { '#6A9955' } else { '#E0BE7C' })
                }
            } catch {}
        }
        if (-not $rows.Count) {
            $t = New-Object Windows.Controls.TextBlock
            $t.Text = 'Nothing established yet.'; $t.Foreground = '#4A5058'; $t.FontSize = 11; $t.TextWrapping = 'Wrap'
            [void]$evidence.Children.Add($t)
            return
        }
        foreach ($r in $rows) {
            $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '0,0,0,8'
            $l = New-Object Windows.Controls.TextBlock
            $l.Text = $r.L; $l.Foreground = '#5A616B'; $l.FontSize = 10
            [void]$sp.Children.Add($l)
            $v = New-Object Windows.Controls.TextBlock
            # A package name IS long, and hiding half of it behind an ellipsis defeats the point of the panel
            $v.Text = $r.V; $v.FontSize = 11.5; $v.TextWrapping = 'Wrap'
            $v.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($r.C)))
            $v.ToolTip = $r.V
            [void]$sp.Children.Add($v)
            [void]$evidence.Children.Add($sp)
        }
    }

    # published for the same reason as the context and the log above: a smoke driver can repaint the flow without a
    # WPF Application object, so the rail and the evidence panel can be checked against a real sheet
    $ctx.Redraw = $drawChips

    $pump = {
        # FOLLOW THE READER, NOT THE LOG. This used to call ScrollToEnd on every tick, outside the loop - so it ran
        # whether or not anything new had arrived, and the timer never stops. Scrolling up during a run was therefore
        # impossible, and so was reading back afterwards: you were dragged to the bottom a few times a second.
        # Now it only sticks to the bottom if that is where you already were, which is what every log viewer does.
        $wasAtBottom = ($sv.ScrollableHeight -le 0) -or ($sv.VerticalOffset -ge ($sv.ScrollableHeight - 24))
        $added = $false
        while ($ctx.Shown -lt $ctx.Activity.Count) {
            $added = $true
            $item = $ctx.Activity[$ctx.Shown]; $ctx.Shown++
            $entry = New-AgentFeedEntry -Item $item
            [void]$feed.Children.Add($entry)
            # Fluent entrance: fade in while rising the last few pixels. A record that simply appears reads as a jump;
            # this reads as it arriving, and it is the only thing in the stream that ever moves.
            try {
                $tt = New-Object Windows.Media.TranslateTransform
                $entry.RenderTransform = $tt
                $entry.BeginAnimation([Windows.UIElement]::OpacityProperty, (& $mkMove 0 1 150 $Ease.Decelerate))
                $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (& $mkMove 8 0 250 $Ease.Decelerate))
            } catch {}
            # WALK THE AGENT TO WHOEVER IS BUSY, carrying what this line is about. Driven by the log itself, so the
            # figure on the road is always showing something that really happened - never an idle animation.
            try {
                $short = "$($item.text)"; if ($short.Length -gt 44) { $short = $short.Substring(0, 44).TrimEnd() + '…' }
                # WHICH LINK, AND WHICH WAY. A command is the agent working on this workstation; anything the AI said
                # came down to the agent; anything the tool reports goes back up as evidence; a question stops both.
                if ("$($item.kind)" -eq 'command') { & $channel 'onEndpoint' $short }
                elseif ("$($item.actor)" -eq 'AI')   { & $channel 'toAgent' $short }
                elseif ("$($item.actor)" -eq 'TOOL') { & $channel 'toAi' $short }
                elseif ("$($item.actor)" -eq 'YOU')  { & $channel 'toYou' 'waiting for you' }
            } catch {
                # The courier is decoration: it must never break the feed. But a silent catch here once hid a
                # hard error for a whole build, so leave a trail rather than nothing.
                $ctx.CourierError = "$($_.Exception.Message)"
                Write-Verbose "courier: $($_.Exception.Message)"
            }
        }
        if ($added -and $wasAtBottom) { $sv.ScrollToEnd() }
    }
    $say = { param($Actor, $Stage, $Text, $Kind)
        Add-AgentActivity -Log $ctx.Activity -Actor $Actor -Stage $Stage -Text $Text -Kind $(if ($Kind) { $Kind } else { 'step' })
        & $pump
    }
    $finish = {
        $ctx.Phase = 'idle'; $ctx.Stage = ''; $pbar.Visibility = 'Collapsed'; $bRun.IsEnabled = $true
        $bReport.IsEnabled = [bool]$ctx.Sheet
        $bPkg.IsEnabled = [bool]($ctx.Sheet -and "$($ctx.Sheet.stages.build.folder)".Trim() -and (Test-Path -LiteralPath "$($ctx.Sheet.stages.build.folder)"))
        & $drawChips
        $lbl.Text = "AI usage so far: $(Format-AgentUsage)$(if ($ctx.Sheet) { "   ·   report: $(Get-AgentSheetDir -Sheet $ctx.Sheet)" })"
        if ($ctx.Sheet -and -not $ctx.ExperienceAsked) { $ctx.ExperienceAsked = $true; & $askExperience }
    }

    # ---- AFTER THE PACKAGE IS HANDED OVER: what did testing teach us? -------------------------------------------------
    # The most valuable thing anybody says about a package is said after they have TESTED it. Said in passing it is
    # gone; written here it trains every future run. The packager writes it however they like; the AI works out what
    # each part of it is - this package, this vendor, this kind of installer, or a house rule - and files it.
    $askExperience = {
        $card = New-Object Windows.Controls.Border
        $card.Background = '#18211C'; $card.BorderBrush = '#5BA97A'; $card.BorderThickness = '1'; $card.CornerRadius = '4'
        $card.Padding = '12'; $card.Margin = '0,4,0,10'
        $sp = New-Object Windows.Controls.StackPanel
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = 'Anything you learned from testing this one?'; $h.Foreground = '#8FE0AE'; $h.FontWeight = 'Bold'; $h.FontSize = 13
        [void]$sp.Children.Add($h)
        $w = New-Object Windows.Controls.TextBlock
        $w.Text = "Write it however you like - what you observed, what you had to change, anything the next person should know. The agent works out whether it is about this package, this vendor, this kind of installer, or all of them, and keeps it. It will not record what it already knows."
        $w.Foreground = '#B7BEC8'; $w.FontSize = 12; $w.TextWrapping = 'Wrap'; $w.Margin = '0,6,0,8'
        [void]$sp.Children.Add($w)
        $box = New-Object Windows.Controls.TextBox
        $box.MinHeight = 70; $box.TextWrapping = 'Wrap'; $box.AcceptsReturn = $true; $box.VerticalScrollBarVisibility = 'Auto'
        $box.Background = '#111317'; $box.Foreground = '#E7E9ED'; $box.BorderBrush = '#2A2F38'; $box.FontSize = 12.5
        [void]$sp.Children.Add($box)
        $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.Margin = '0,10,0,0'
        $keep = New-Object Windows.Controls.Button; $keep.Content = 'Remember this'; $keep.Padding = '16,5'; $keep.Margin = '0,0,8,0'
        try { $keep.Style = $win.FindResource('PbAccentButton') } catch {}
        $no = New-Object Windows.Controls.Button; $no.Content = 'Nothing to add'; $no.Padding = '14,5'
        [void]$btns.Children.Add($keep); [void]$btns.Children.Add($no)
        [void]$sp.Children.Add($btns)
        $card.Child = $sp
        [void]$feed.Children.Add($card); $sv.ScrollToEnd()
        $no.add_Click({ $card.IsEnabled = $false }.GetNewClosure())
        $keep.add_Click({
            $txt = "$($box.Text)".Trim()
            if (-not $txt) { $card.IsEnabled = $false; return }
            $card.IsEnabled = $false
            & $say 'YOU' 'handover' $txt 'step'
            try {
                $r = Invoke-AgentExperienceIntake -Text $txt -Sheet $ctx.Sheet
                foreach ($e in @($r.stored)) { & $say 'AI' 'handover' "Remembered [$($e.scope)]: $($e.text)" 'step' }
                foreach ($nk in @($r.notKept)) { & $say 'AI' 'handover' "Not kept - $($nk.what): $($nk.why)" 'step' }
                if ("$($r.summary)".Trim()) { & $say 'AI' 'handover' "$($r.summary)" 'step' }
                elseif (-not @($r.stored).Count) { & $say 'AI' 'handover' "$($r.note)" 'step' }
            } catch { & $say 'TOOL' 'handover' "Could not record that: $($_.Exception.Message)" 'error' }
        }.GetNewClosure())
    }

    # ---- the driver: pick the next stage and run it ------------------------------------------------------------------------
    $startStage = {
        param($Id)
        $ctx.Stage = $Id; $ctx.Phase = 'running'; $pbar.Visibility = 'Visible'; $bRun.IsEnabled = $false
        $def = Get-AgentStageDef -Id $Id
        $actor = if ("$($def.Owner)" -eq 'tool') { 'TOOL' } else { 'AI' }
        & $say $actor $Id $(if ("$($def.Say)".Trim()) { "$($def.Say)" } else { "$($def.Title)" }) 'stage'
        & $drawChips
        # handover writes files through the export, which lives with the window - run it here, not in a runspace
        if ($Id -eq 'handover') {
            try {
                $o = Export-AgentEvaluation -Ctx @{ Sheet = $ctx.Sheet; Result = $ctx.Result; RunInfo = $ctx.Run }
                [void](Set-AgentStage -Sheet $ctx.Sheet -Id 'handover' -Status 'done' -Note "sheet + handover + snapshot report" -Data @{ dir = "$($o.Dir)" })
                & $say 'TOOL' $Id "Wrote the evaluation sheet, agent-handover.json and the snapshot report to $($o.Dir)." 'step'
            } catch {
                [void](Set-AgentStage -Sheet $ctx.Sheet -Id 'handover' -Status 'failed' -Note "$($_.Exception.Message)")
                & $say 'TOOL' $Id "Handover failed: $($_.Exception.Message)" 'error'
            }
            $ctx.Phase = 'idle'; $pbar.Visibility = 'Collapsed'
            & $drawChips; & $advance; return
        }
        $arg = @{ id = $Id; sheet = $ctx.Sheet; activity = $ctx.Activity; actor = $actor
                  with = @{ Folder = "$($ctx.Folder)"; BuiltScript = ''; MaxRounds = 3 } }
        if ($Id -eq 'evaluate') {
            # THE AI'S LINES, OR NOTHING - the plan's first line and its alternatives, reduced to arguments (the tool
            # builds the launch itself). The tool never adds a line of its own.
            $p = Get-AgentRunProposal -Sheet $ctx.Sheet
            $cands = @($p.Candidates)
            $local = if (Get-Command Copy-InstallerLocal -ErrorAction SilentlyContinue) { Copy-InstallerLocal -ExePath $p.Installer } else { $p.Installer }
            if (-not $local -or -not (Test-Path -LiteralPath $local)) { $local = $p.Installer }
            $arg.proposal = $p; $arg.candidates = $cands; $arg.installer = $local; $arg.analyze = $script:AgentAnalyzeScript
        }
        $ctx.Box = Start-AgentRunspace -Arg $arg -Script (Get-AgentStageScript -Id $Id)
    }

    # THIS ORDER HAS BEEN WORKED ON BEFORE. Say exactly how far it got and when, and let the packager choose.
    $askResume = {
        param($Old, $Path, $Name, $Folder)
        $ctx.Phase = 'ask'
        $when = try { (Get-Item -LiteralPath $Path).LastWriteTime.ToString('ddd d MMM, HH:mm') } catch { 'earlier' }
        $done = @(); $left = @()
        try {
            foreach ($s in @(Get-AgentFlow -Sheet $Old)) {
                if ("$($s.state)" -in 'done', 'skipped') { $done += "$($s.title)" } else { $left += "$($s.title)" }
            }
        } catch {}
        $card = New-Object Windows.Controls.Border
        $card.Background = '#2A2618'; $card.BorderBrush = '#E0BE7C'; $card.BorderThickness = '1'; $card.CornerRadius = '4'
        $card.Padding = '12'; $card.Margin = '0,4,0,10'
        $sp = New-Object Windows.Controls.StackPanel
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = "This order was worked on before - $when."
        $h.Foreground = '#E0BE7C'; $h.FontSize = 13; $h.FontWeight = 'SemiBold'; $h.TextWrapping = 'Wrap'
        [void]$sp.Children.Add($h)
        $d = New-Object Windows.Controls.TextBlock
        $d.Text = @"
$(if (@($done).Count) { "Already done: $((@($done)) -join ', ')." } else { 'Nothing was finished.' })
$(if (@($left).Count) { "Still to do: $((@($left)) -join ', ')." })
$(if ("$($Old.verification.verdict)".Trim()) { "Last verification said: $("$($Old.verification.verdict)".ToUpper())." })

Continuing keeps those results and carries on from where it stopped. That is right when nothing has changed since -
but if you have touched the source, fixed the order, or just want it done properly from the start, take a fresh run:
the finished stages were judged against what was there THEN, not what is there now.

Either way the AI starts a new conversation - it re-reads what it needs.
"@
        $d.Foreground = '#E7E9ED'; $d.FontSize = 12.5; $d.TextWrapping = 'Wrap'; $d.Margin = '0,8,0,0'
        [void]$sp.Children.Add($d)
        $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.Margin = '0,12,0,0'
        $cont = New-Object Windows.Controls.Button; $cont.Content = 'Continue where it stopped'; $cont.Padding = '16,5'; $cont.Margin = '0,0,8,0'
        $fresh = New-Object Windows.Controls.Button; $fresh.Content = 'Start fresh'; $fresh.Padding = '16,5'
        try { $fresh.Style = $win.FindResource('PbAccentButton') } catch {}
        [void]$btns.Children.Add($cont); [void]$btns.Children.Add($fresh); [void]$sp.Children.Add($btns)
        $card.Child = $sp; $ctx.PendingCard = $card
        [void]$feed.Children.Add($card); $sv.ScrollToEnd()
        $ctx.ResumeOld = $Old; $ctx.ResumeName = "$Name"; $ctx.ResumeFolder = "$Folder"; $ctx.ResumePath = "$Path"
        $cont.add_Click({
            $ctx.PendingCard.IsEnabled = $false
            $ctx.Sheet = $ctx.ResumeOld
            & $say 'YOU' '' 'Continue where it stopped.' 'step'
            & $say 'TOOL' '' "Carrying on with $($ctx.ResumeName) from $($ctx.ResumePath)." 'step'
            $ctx.Phase = 'idle'; & $drawChips; & $advance
        })
        $fresh.add_Click({
            $ctx.PendingCard.IsEnabled = $false
            # keep the old sheet - it is evidence of what happened last time, not rubbish
            try {
                $bak = "$($ctx.ResumePath)" -replace '\.json$', ".$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                Move-Item -LiteralPath $ctx.ResumePath -Destination $bak -Force -ErrorAction Stop
                & $say 'TOOL' '' "Starting fresh. Last time's sheet is kept as $(Split-Path -Leaf $bak)." 'step'
            } catch { & $say 'TOOL' '' "Starting fresh (the old sheet could not be set aside: $($_.Exception.Message))." 'step' }
            $ctx.Sheet = New-AgentSheet -PkgName "$($ctx.ResumeName)" -Folder "$($ctx.ResumeFolder)"
            & $say 'YOU' '' 'Start fresh.' 'step'
            & $say 'TOOL' '' "Working on $($ctx.ResumeName)" 'step'
            $ctx.Phase = 'idle'; & $drawChips; & $advance
        })
    }

    $askApproval = {
        param($Id, $Question)
        $ctx.Phase = 'approve'; $pbar.Visibility = 'Collapsed'
        $card = New-Object Windows.Controls.Border
        $card.Background = '#2A2618'; $card.BorderBrush = '#E0BE7C'; $card.BorderThickness = '1,1,1,1'; $card.CornerRadius = '4'
        $card.Padding = '12'; $card.Margin = '0,4,0,10'
        $sp = New-Object Windows.Controls.StackPanel
        $q = New-Object Windows.Controls.TextBlock
        $q.Text = $Question; $q.Foreground = '#E7E9ED'; $q.FontSize = 12.5; $q.TextWrapping = 'Wrap'
        [void]$sp.Children.Add($q)
        $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.Margin = '0,10,0,0'
        $yes = New-Object Windows.Controls.Button; $yes.Content = 'Approve'; $yes.Padding = '18,5'; $yes.Margin = '0,0,8,0'
        try { $yes.Style = $win.FindResource('PbAccentButton') } catch {}
        $no = New-Object Windows.Controls.Button; $no.Content = 'Skip this step'; $no.Padding = '14,5'
        [void]$btns.Children.Add($yes); [void]$btns.Children.Add($no); [void]$sp.Children.Add($btns)
        $card.Child = $sp; $ctx.PendingCard = $card; [void]$feed.Children.Add($card); $sv.ScrollToEnd()
        $yes.add_Click({
            $ctx.PendingCard.IsEnabled = $false; $ctx.Approved[$ctx.PendingId] = $true
            & $say 'YOU' $ctx.PendingId 'Approved.' 'step'
            & $startStage $ctx.PendingId
        })
        $no.add_Click({
            $ctx.PendingCard.IsEnabled = $false; $ctx.Approved[$ctx.PendingId] = 'skip'
            [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.PendingId -Status 'skipped' -Note 'skipped by the packager')
            & $say 'YOU' $ctx.PendingId 'Skipped.' 'step'
            & $advance
        })
    }

    # A stage failed. Do not end the run - a packager would decide what to do, so ask them.
    # A FAILURE GOES TO THE AGENT BEFORE IT GOES TO YOU.
    # A packager who hit this would look at the error and try the obvious thing before interrupting anybody. So the
    # AI gets the failure first: it says whose fault it is and what to do - run it again, run it differently, carry
    # on without it, or get a person. Only the last one shows you a card. Bounded, so a stage that keeps failing
    # still reaches you instead of looping.
    $troubleshootThen = {
        param($Id, $Why)
        $ctx.TsCount = @{} + $(if ($ctx.TsCount) { $ctx.TsCount } else { @{} })
        $n = [int]$ctx.TsCount["$Id"]
        if ($n -ge 2 -or -not (Test-AgentEnabled)) {
            if ($n -ge 2) { & $say 'TOOL' $Id "This has failed $n times after troubleshooting - over to you." 'error' }
            & $askRecovery $Id $Why; return
        }
        $ctx.TsCount["$Id"] = $n + 1
        $ctx.Phase = 'troubleshoot'; $pbar.Visibility = 'Visible'
        & $say 'AI' $Id 'Looking at what went wrong before bothering you.' 'stage'
        # New-AgentRunspaceArg WAS NEVER DEFINED. This line threw CommandNotFoundException every single time
        # troubleshoot was reached - after the feed had already said "Looking at what went wrong", and before
        # Start-AgentRunspace was called. So $ctx.TsBox.Done never became true, the timer polled a flag that could
        # never be set, and the window hung with Run greyed out and no way back but killing it. The activity log has
        # to travel too, or the stage cannot report anything it does.
        $arg = @{ sheet = $ctx.Sheet; activity = $ctx.Activity; id = "$Id"; why = "$Why" }
        $box = Start-AgentRunspace -Arg $arg -Script @'
param($a, $box)
$log = $a.activity; $script:AgentActivityLog = $log
$r = Invoke-AgentTroubleshoot -Sheet $a.sheet -Stage "$($a.id)" -Error "$($a.why)" -Progress { param($t) $box.Progress = "$t" }
@{ sheet = $a.sheet; result = $r }
'@
        $ctx.TsBox = $box
        $ctx.TsStarted = Get-Date
        # $Id and $Why go on the context, NOT into a closure. The handler below used .GetNewClosure() purely to keep
        # them - and a closure cannot see this session's FUNCTIONS, so Stop-AgentRunspace threw the moment the work
        # finished, WPF swallowed it, and the window waited forever on a runspace that had already answered. Putting
        # the two values somewhere the handler can reach removes the need for the closure entirely.
        $ctx.TsId = "$Id"; $ctx.TsWhy = "$Why"
        $tsTimer = New-Object Windows.Threading.DispatcherTimer
        $ctx.TsTimer = $tsTimer   # same reason as the consult timer: a handler outlives this scope, $ctx does not
        $tsTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $tsTimer.add_Tick({
          try {
            $Id = "$($ctx.TsId)"; $Why = "$($ctx.TsWhy)"
            if (-not $ctx.TsBox.Done) {
                if ("$($ctx.TsBox.Progress)".Trim()) { $pbar.ToolTip = "$($ctx.TsBox.Progress)"; if ("$($ctx.TsBox.Progress)" -match '^model:') { & $channel 'toAi' 'asking the AI what went wrong' } }
                # A WATCHDOG, BECAUSE THIS WAIT USED TO BE UNCONDITIONAL. If the runspace dies before it sets Done -
                # and one did, with no request ever reaching the model - this timer polls a flag that will never be
                # set, and the window sits there looking busy forever with the Run button greyed out. There is no
                # recovering from that except killing the process. Waiting is fine; waiting without end is not.
                # Generous on purpose: one call already allows 180s, and the client retries three times and then
                # falls back to another model, so a legitimately slow gateway can take ten minutes. This is the
                # difference between slow and never, not between slow and fast.
                $waited = try { ((Get-Date) - $ctx.TsStarted).TotalSeconds } catch { 0 }
                if ($waited -gt 900) {
                    $ctx.TsTimer.Stop()
                    $err = "$($ctx.TsBox.Error)".Trim()
                    try { Stop-AgentRunspace -Box $ctx.TsBox } catch {}
                    $pbar.Visibility = 'Collapsed'; $ctx.Phase = 'idle'
                    & $say 'TOOL' $Id "Gave up waiting for the agent to work out what went wrong - $([int]$waited)s with no answer$(if ($err) { ": $err" } else { ' and no error either, so it stopped before it got as far as asking' }). Over to you." 'error'
                    & $askRecovery $Id $Why
                }
                return
            }
            $ctx.TsTimer.Stop()
            Stop-AgentRunspace -Box $ctx.TsBox
            $res = $ctx.TsBox.Result
            $pbar.Visibility = 'Collapsed'; $ctx.Phase = 'idle'
            if ($res.sheet) { $ctx.Sheet = $res.sheet }
            $r = $res.result
            if (-not $r) { & $askRecovery $ctx.PendingId $Why; return }
            & $say 'AI' $Id $(if ("$($r.narration)".Trim()) { "$($r.narration)" } else { "$($r.whatHappened)" }) 'step'
            if ("$($r.toolProblem.isToolBug)" -eq 'True' -or [bool]$r.toolProblem.isToolBug) {
                & $say 'AI' $Id "This looks like a fault in the agent itself: $($r.toolProblem.what)$(if ("$($r.toolProblem.whereYouThinkItIs)".Trim()) { " - probably $($r.toolProblem.whereYouThinkItIs)" })" 'error'
            }
            switch ("$($r.recommend)") {
                'retry_same'    { & $say 'AI' $Id "Trying again: $($r.why)" 'step'
                                  try { $ctx.Sheet.stages.Remove("$Id") } catch {}
                                  & $startStage $Id }
                'retry_changed' { & $say 'AI' $Id "Trying again, differently: $($r.fixDescription)" 'step'
                                  try { $ctx.Sheet.stages.Remove("$Id") } catch {}
                                  & $startStage $Id }
                'carry_on'      { & $say 'AI' $Id "Carrying on without it: $($r.why)" 'step'
                                  [void](Set-AgentStage -Sheet $ctx.Sheet -Id $Id -Status 'skipped' -Note "the agent judged this not essential: $($r.why)")
                                  & $drawChips; & $advance }
                default         { if ("$($r.forThePackager)".Trim()) { & $say 'AI' $Id "$($r.forThePackager)" 'step' }
                                  & $askRecovery $Id $(if ("$($r.whatHappened)".Trim()) { "$($r.whatHappened)" } else { $Why }) }
            }
          } catch {
            # never leave the window waiting on work that has already finished
            $ctx.TsTimer.Stop(); $pbar.Visibility = 'Collapsed'; $ctx.Phase = 'idle'
            & $say 'TOOL' "$($ctx.TsId)" "Something went wrong handling that failure: $($_.Exception.Message)" 'error'
            & $askRecovery "$($ctx.TsId)" "$($ctx.TsWhy)"
          }
        })
        $tsTimer.Start()
    }

    $askRecovery = {
        param($Id, $Why)
        $ctx.Phase = 'recover'; $pbar.Visibility = 'Collapsed'; $ctx.PendingId = "$Id"
        $card = New-Object Windows.Controls.Border
        $card.Background = '#2C1E1C'; $card.BorderBrush = '#F48771'; $card.BorderThickness = '1'; $card.CornerRadius = '4'
        $card.Padding = '12'; $card.Margin = '0,4,0,10'
        $sp = New-Object Windows.Controls.StackPanel
        $q = New-Object Windows.Controls.TextBlock
        $q.Text = "$((Get-AgentStageDef -Id $Id).Title) failed:`n$Why`n`nThe rest of the order is still usable. What would you like to do?"
        $q.Foreground = '#E7E9ED'; $q.FontSize = 12.5; $q.TextWrapping = 'Wrap'
        [void]$sp.Children.Add($q)
        $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.Margin = '0,10,0,0'
        $again = New-Object Windows.Controls.Button; $again.Content = 'Try again'; $again.Padding = '16,5'; $again.Margin = '0,0,8,0'
        try { $again.Style = $win.FindResource('PbAccentButton') } catch {}
        $skip = New-Object Windows.Controls.Button; $skip.Content = 'Carry on without it'; $skip.Padding = '14,5'; $skip.Margin = '0,0,8,0'
        $stop = New-Object Windows.Controls.Button; $stop.Content = 'Stop here'; $stop.Padding = '14,5'
        foreach ($b in @($again, $skip, $stop)) { [void]$btns.Children.Add($b) }
        [void]$sp.Children.Add($btns)
        $card.Child = $sp; $ctx.PendingCard = $card
        [void]$feed.Children.Add($card); $sv.ScrollToEnd()
        $again.add_Click({
            $ctx.PendingCard.IsEnabled = $false
            try { $ctx.Sheet.stages.Remove("$($ctx.PendingId)") } catch {}   # forget the failure so the flow offers it again
            & $say 'YOU' $ctx.PendingId 'Try again.' 'step'
            & $startStage $ctx.PendingId
        })
        $skip.add_Click({
            $ctx.PendingCard.IsEnabled = $false
            [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.PendingId -Status 'skipped' -Note 'failed, and the packager chose to carry on without it')
            & $say 'YOU' $ctx.PendingId 'Carry on without it.' 'step'
            & $advance
        })
        $stop.add_Click({
            $ctx.PendingCard.IsEnabled = $false
            $ctx.Stop = $true
            & $say 'YOU' $ctx.PendingId 'Stop here.' 'step'
            & $finish
        })
    }

    # The AI needs something only a person can give. Show the request the way a colleague would ask: what, the exact
    # command, what to send back - and let the packager say when it is done.
    $askHuman = {
        param($Id, $Need)
        $ctx.Phase = 'human'; $pbar.Visibility = 'Collapsed'; $ctx.PendingId = "$Id"
        $card = New-Object Windows.Controls.Border
        $card.Background = '#2A2618'; $card.BorderBrush = '#E0BE7C'; $card.BorderThickness = '1'; $card.CornerRadius = '4'
        $card.Padding = '12'; $card.Margin = '0,4,0,10'
        $sp = New-Object Windows.Controls.StackPanel
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = "The agent needs your help"; $h.Foreground = '#E0BE7C'; $h.FontWeight = 'Bold'; $h.FontSize = 13
        [void]$sp.Children.Add($h)
        $w = New-Object Windows.Controls.TextBlock
        $w.Text = "$($Need.what)"; $w.Foreground = '#E7E9ED'; $w.FontSize = 12.5; $w.TextWrapping = 'Wrap'; $w.Margin = '0,6,0,0'
        [void]$sp.Children.Add($w)
        if ("$($Need.exactCommand)".Trim()) {
            $lbl = New-Object Windows.Controls.TextBlock
            $lbl.Text = 'Run this:'; $lbl.Foreground = '#8A93A0'; $lbl.FontSize = 11; $lbl.Margin = '0,8,0,2'
            [void]$sp.Children.Add($lbl)
            $b = New-Object Windows.Controls.Border
            $b.Background = '#111317'; $b.BorderBrush = '#2A2F38'; $b.BorderThickness = '1'; $b.CornerRadius = '3'; $b.Padding = '8,5'
            $c = New-Object Windows.Controls.TextBox
            $c.Text = "$($Need.exactCommand)"; $c.IsReadOnly = $true; $c.BorderThickness = '0'; $c.Background = 'Transparent'
            $c.Foreground = '#D7FFD7'; $c.FontFamily = 'Consolas'; $c.FontSize = 11.5; $c.TextWrapping = 'Wrap'
            $b.Child = $c; [void]$sp.Children.Add($b)
        }
        if ("$($Need.sendBack)".Trim()) {
            $s2 = New-Object Windows.Controls.TextBlock
            $s2.Text = "Then: $($Need.sendBack)"; $s2.Foreground = '#B7BEC8'; $s2.FontSize = 12; $s2.TextWrapping = 'Wrap'; $s2.Margin = '0,8,0,0'
            [void]$sp.Children.Add($s2)
        }
        $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.Margin = '0,10,0,0'
        $done = New-Object Windows.Controls.Button; $done.Content = "I've done it - carry on"; $done.Padding = '16,5'; $done.Margin = '0,0,8,0'
        try { $done.Style = $win.FindResource('PbAccentButton') } catch {}
        $later = New-Object Windows.Controls.Button; $later.Content = 'Carry on without it'; $later.Padding = '14,5'
        # ANYTHING YOU TELL IT IS KEPT. A packager who explains something once should not have to explain it again
        # next month on the next version - so what is typed here goes into the agent's memory and travels with every
        # future run for this vendor.
        $nl = New-Object Windows.Controls.TextBlock
        $nl.Text = 'Anything the agent should know? It will remember this for next time.'
        $nl.Foreground = '#8A93A0'; $nl.FontSize = 11; $nl.Margin = '0,10,0,3'
        [void]$sp.Children.Add($nl)
        $note = New-Object Windows.Controls.TextBox
        $note.MinHeight = 46; $note.TextWrapping = 'Wrap'; $note.AcceptsReturn = $true
        $note.Background = '#111317'; $note.Foreground = '#E7E9ED'; $note.BorderBrush = '#2A2F38'; $note.FontSize = 12
        [void]$sp.Children.Add($note)
        $ctx.PendingNote = $note
        [void]$btns.Children.Add($done); [void]$btns.Children.Add($later)
        [void]$sp.Children.Add($btns)
        $card.Child = $sp; $ctx.PendingCard = $card
        [void]$feed.Children.Add($card); $sv.ScrollToEnd()
        $keepNote = {
            $txt = ''
            try { $txt = "$($ctx.PendingNote.Text)".Trim() } catch {}
            if (-not $txt) { return }
            $vend = "$($ctx.Sheet.identity.vendor)".Trim()
            $scope = if ($vend) { "vendor:$vend" } else { 'global' }
            try {
                [void](Add-AgentMemory -Text $txt -Scope $scope -Why "said while packaging $($ctx.Sheet.package)" -Source 'packager')
                & $say 'YOU' $ctx.PendingId "Noted - the agent will remember this ($scope)." 'step'
            } catch {}
        }
        $done.add_Click({
            $ctx.PendingCard.IsEnabled = $false
            & $keepNote
            [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.PendingId -Status 'done' -Note 'the packager did what was asked')
            & $say 'YOU' $ctx.PendingId "Done - carrying on." 'step'
            & $advance
        })
        $later.add_Click({
            $ctx.PendingCard.IsEnabled = $false
            & $keepNote
            [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.PendingId -Status 'skipped' -Note 'the packager chose to carry on without it')
            & $say 'YOU' $ctx.PendingId 'Carrying on without it.' 'step'
            & $advance
        })
    }

    $advance = {
        if ($ctx.Stop) { & $finish; return }
        # a stage that came back "waiting" is asking the packager for something - show the request
        if ($ctx.Sheet -and "$(Get-AgentStageStatus -Sheet $ctx.Sheet -Id 'prepare')" -eq 'waiting' -and -not $ctx.Approved['prepare-asked']) {
            $ctx.Approved['prepare-asked'] = $true
            $need = $ctx.Sheet.prepare.humanNeeded
            & $say 'AI' 'prepare' "I need something only you can do: $($need.what)" 'step'
            & $askHuman 'prepare' $need
            return
        }
        $flow = @(Get-AgentFlow -Sheet $ctx.Sheet)
        # walk the pipeline IN ORDER: the first stage that is ready, or a gate still waiting for you. Taking every
        # ready stage first would build the package before the evaluation that is supposed to inform it.
        $next = $null; $gate = $null
        foreach ($s in $flow) {
            if ($s.state -eq 'ready') { $next = $s; break }
            if ($s.state -eq 'waiting' -and (Get-AgentStageDef -Id $s.id).Gate -and -not $ctx.Approved["$($s.id)"]) { $gate = $s; break }
        }
        if (-not $next) {
            if ($gate) {
                $p = Get-AgentRunProposal -Sheet $ctx.Sheet
                $ctx.PendingId = "$($gate.id)"
                if (-not $p) {
                    [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.PendingId -Status 'skipped' -Note 'no installer to run')
                    & $say 'TOOL' $ctx.PendingId 'No installer to run - skipping the evaluation.' 'error'
                    & $advance; return
                }
                # NOTHING RUNS ON THIS MACHINE THAT THE AI DID NOT CHOOSE. The tool used to fill this gap with a
                # command of its own and the evaluation proceeded on it; the AI then reasoned about the result as
                # though it were evidence about the package. A missing decision is a failure of the AI's, and it
                # goes back to the AI - the troubleshoot step this failure raises is where it gets made.
                if (-not $p.Decided) {
                    [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.PendingId -Status 'failed' -Note "$($p.Why)")
                    & $say 'TOOL' $ctx.PendingId "Nothing will be installed: $($p.Why). The tool does not choose what runs here." 'error'
                    & $troubleshootThen $ctx.PendingId "$($p.Why)"
                    return
                }
                $cands = [Math]::Max(@($p.Candidates).Count, @($p.Sequence).Count)
                & $say 'TOOL' $ctx.PendingId 'Waiting for your approval before installing anything on this machine.' 'step'
                $elev = $false
try { $elev = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
$nAttempts = $(if ($cands) { $cands } else { 1 })
& $askApproval $ctx.PendingId "Evaluate on THIS machine?`n`nThe agent takes a baseline snapshot, then tries $nAttempts silent command(s) on $($p.Name) one at a time until one installs without waiting for a click, then snapshots again and classifies what changed.`n`nThis really installs the application here.$(if ($elev) { ' The agent is running elevated, so Windows will not ask again.' } else { " The agent is NOT elevated, so Windows will ask for permission on each attempt - up to $nAttempts time(s). Starting the agent from an elevated prompt avoids that." })"
                return
            }
            & $finish
            # "7 of 8 done" reads like something failed. A skipped stage is a DECISION - name it and say why.
            $v = $ctx.Sheet.verification
            $done = @($flow | Where-Object { $_.state -eq 'done' })
            $skipped = @($flow | Where-Object { $_.state -eq 'skipped' })
            $failed = @($flow | Where-Object { $_.state -eq 'failed' })
            # A RUN THAT STOPPED IS NOT A RUN THAT FINISHED. Stages left neither done nor deliberately skipped mean
            # the flow ran out of anything it was allowed to do - a blocking gap, usually - and saying "Finished,
            # 3 stages done" for that is the most misleading thing this window can say. Name what did not happen.
            $stalled = @($flow | Where-Object { $_.state -notin 'done', 'skipped', 'failed' })
            $line = if (@($stalled).Count) { "STOPPED before the work was done - $(@($stalled).Count) stage(s) never ran: $((@($stalled) | ForEach-Object { $_.title }) -join ', ')" }
                    else { "Finished. $(@($done).Count) stage(s) done" }
            if (@($stalled).Count) {
                $blockers = @($ctx.Sheet.gaps | Where-Object { "$($_.severity)" -eq 'block' })
                $line += if (@($blockers).Count) { ".  What stopped it: $((@($blockers) | ForEach-Object { "$($_.text)" }) -join ' | ')" }
                         elseif ("$($ctx.Sheet.status)" -eq 'blocked') { '.  The order is marked blocked.' }
                         else { '.  Nothing was ready to run next - see the stage notes.' }
                $line += "  $(@($done).Count) stage(s) did complete"
            }
            if (@($skipped).Count) { $line += ", $(@($skipped).Count) not needed ($((@($skipped) | ForEach-Object { "$($_.title): $($ctx.Sheet.stages["$($_.id)"].note)" }) -join '; '))" }
            if (@($failed).Count) { $line += ", $(@($failed).Count) FAILED ($((@($failed) | ForEach-Object { $_.title }) -join ', '))" }
            $line += '.'
            if ($v -and $v.verdict) { $line += "  Verification: $("$($v.verdict)".ToUpper())." }
            if ("$($ctx.Sheet.stages.build.folder)".Trim()) { $line += "  Package: $($ctx.Sheet.stages.build.folder)" }
            & $say 'TOOL' '' $line $(if (@($failed).Count -or @($stalled).Count) { 'error' } else { 'step' })
            return
        }
        & $startStage $next.id
    }

    # ---- events -------------------------------------------------------------------------------------------------------
    $bKey.add_Click({ if (Show-AgentKeyDialog) { $lbl.Text = "Key: $(Get-AgentKeySource) · model $(Get-AgentModel)" } })
    $bBrowse.add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select the order folder'
        $repo = try { Get-Setting 'RepositoryPath' } catch { '' }
        if ("$($txtFolder.Text)".Trim() -and (Test-Path -LiteralPath $txtFolder.Text)) { $dlg.SelectedPath = $txtFolder.Text }
        elseif ($repo -and (Test-Path -LiteralPath $repo)) { $dlg.SelectedPath = $repo }
        if ($dlg.ShowDialog() -eq 'OK') { $txtFolder.Text = $dlg.SelectedPath }
    })
    $bReport.add_Click({ if ($ctx.Sheet) { $p = Save-AgentSheet -Sheet $ctx.Sheet; try { Start-Process $p.Html } catch {} } })
    $bPkg.add_Click({ $f = "$($ctx.Sheet.stages.build.folder)"; if ($f -and (Test-Path -LiteralPath $f)) { try { Start-Process explorer.exe -ArgumentList "`"$f`"" } catch {} } })
    $bRun.add_Click({
        $folder = "$($txtFolder.Text)".Trim('"', ' ')
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { $lbl.Text = 'Pick an order folder first.'; $lbl.Foreground = '#F48771'; return }
        if (-not (Test-AgentHasKey)) { if (-not (Show-AgentKeyDialog)) { return } }
        $ctx.Folder = $folder; $ctx.Stop = $false
        $name = Split-Path -Leaf $folder
        $lbl.Foreground = '#B7BEC8'
        # PICKING UP SOMEBODY ELSE'S HALF-FINISHED WORK IS A DECISION, NOT A DEFAULT.
        # This used to load the old sheet and carry on without asking. That is the right thing about half the time -
        # and the other half the packager has changed the source, fixed the order, or simply wants a clean run, and
        # silently resuming means stages are marked done that were never done against what is there NOW.
        $prev = Join-Path (Get-AgentSheetDir -Sheet @{ package = $name }) 'evaluation-sheet.json'
        $old = $null
        if (Test-Path -LiteralPath $prev) { $old = try { Read-AgentSheet -Path $prev } catch { $null } }
        if ($old) { & $askResume $old $prev $name $folder; return }
        $ctx.Sheet = New-AgentSheet -PkgName $name -Folder $folder
        & $say 'TOOL' '' "Working on $name" 'step'
        & $advance
    })

    # ---- one timer watches the running stage --------------------------------------------------------------------------
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.add_Tick({
        # Lay the road out here too. ContentRendered and SizeChanged both fire before the canvas has measured itself,
        # so the right-hand card stayed at its placeholder position and the road had almost no length. This is cheap,
        # idempotent, and by the time the first tick runs the window really has a width.
        & $pump
        if ($ctx.Phase -ne 'running') { return }
        $box = $ctx.Box
        if ($box.Progress) {
            $lbl.Text = "$($ctx.Stage) - $($box.Progress)"
            # A stage in progress is still a message in flight: up to the AI while it waits for an answer, or down on
            # this workstation while something runs here. Only send it when the leg actually changes, so the strip is
            # not restarting the same animation on every tick.
            try {
                $prog = "$($box.Progress)"
                $leg = if ($prog -match '^\s*model:') { 'toAi' } else { 'onEndpoint' }
                if ($leg -ne $ctx.ChannelAt) {
                    $what = if ($leg -eq 'toAi') { ($prog -replace '^\s*model:\s*', '') } else { $prog }
                    if ($what.Length -gt 44) { $what = $what.Substring(0, 44).TrimEnd() + '…' }
                    & $channel $leg $what
                }
            } catch {}
        }
        # THE WATCHER. Everything else here waits on $box.Done and nothing ever asked whether waiting was still
        # sensible - so a stage that wedged (an installer holding a pipe open, a model call that never came back)
        # left the window saying "still working" until somebody killed it. Silence WHILE work happens is correct and
        # expected; silence after work has stopped is a fault, and the difference is whether anything is still moving.
        # Progress text changing is the pulse. When it stops: look, say so, and eventually hand it back to the human.
        if (-not $box.Done) {
            $nowProg = "$($box.Progress)"
            if ($nowProg -ne "$($ctx.LastProgress)") { $ctx.LastProgress = $nowProg; $ctx.LastProgressAt = Get-Date; $ctx.StallTold = 0 }
            if (-not $ctx.LastProgressAt) { $ctx.LastProgressAt = Get-Date }
            $still = try { ((Get-Date) - $ctx.LastProgressAt).TotalSeconds } catch { 0 }
            # NOTHING HAS MOVED FOR THREE MINUTES - SO TELL THE AI, NOT JUST THE PACKAGER.
            # Reporting a stall into the feed leaves the one thing that can reason about it - the AI - sitting outside
            # the room. It is the only party that knows what this stage was supposed to be doing. So: gather what the
            # machine looks like, hand it over, and let it say whether this is a big install still working or a dialog
            # nobody is going to click. "Slow" and "stuck" look identical from here and different to the AI.
            if ($still -gt 180 -and [int]$ctx.StallTold -lt 1 -and -not $ctx.Consulting) {
                $ctx.StallTold = 1
                & $say 'TOOL' $ctx.Stage "Nothing has moved for $([int]$still)s. Last thing it said: $(if ($nowProg) { $nowProg } else { '(nothing)' }). Asking the AI to look at the machine." 'error'
                $shotPath = ''; $onScreen = 'nothing with a window'
                try {
                    $shot = Get-AgentScreenshot -Why "the $($ctx.Stage) stage has not reported anything for $([int]$still)s"
                    if ($shot.ok) {
                        $shotPath = "$($shot.path)"
                        if (@($shot.visibleWindows).Count) { $onScreen = (@($shot.visibleWindows) | ForEach-Object { "$($_.process): $($_.title)" }) -join ' | ' }
                    }
                } catch {}
                $procs = ''
                try { $procs = (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.CPU -gt 1 -or $_.MainWindowHandle -ne 0 } | Sort-Object CPU -Descending | Select-Object -First 12 | ForEach-Object { "$($_.ProcessName) ($($_.Id))$(if ($_.MainWindowTitle) { " [$($_.MainWindowTitle)]" })" }) -join ', ') } catch {}
                & $askAgent @"
The '$($ctx.Stage)' stage has not reported anything for $([int]$still) seconds. Nothing is broken that I can see - it may simply be a long install or a big snapshot - but I cannot tell the difference and you can.

Last thing it reported: $(if ($nowProg) { $nowProg } else { '(it never reported anything)' })

On screen right now: $onScreen
$(if ($shotPath) { "A screenshot was taken: $shotPath - open it with read_document if you want to look." })

Busiest processes / anything with a window: $(if ($procs) { $procs } else { '(nothing notable)' })

Is this still working, or is it stuck? Look at whatever you need to - run_powershell and take_screenshot both still work while this runs. If it is stuck, say so in stopTheRunningStage and I will stop it and bring you the failure. If it is just slow, say so and I will leave it alone.
"@
            }
            # and if the AI says nothing and nothing moves for twelve minutes, stop pretending
            if ($still -gt 720 -and [int]$ctx.StallTold -lt 2) {
                $ctx.StallTold = 2
                $stage = "$($ctx.Stage)"
                & $say 'TOOL' $stage "Twelve minutes with nothing moving - I am not waiting any longer. The stage is stopped." 'error'
                try { Stop-AgentRunspace -Box $box } catch {}
                $ctx.Phase = 'idle'; $pbar.Visibility = 'Collapsed'
                [void](Set-AgentStage -Sheet $ctx.Sheet -Id $stage -Status 'failed' -Note "stopped: nothing moved for $([int]$still)s, last progress '$nowProg'")
                & $drawChips
                & $troubleshootThen $stage "the stage stopped responding - nothing moved for $([int]$still)s, and the last thing it reported was '$nowProg'"
            }
            return
        }
        $ctx.StallTold = 0; $ctx.LastProgress = ''; $ctx.LastProgressAt = $null
        Stop-AgentRunspace -Box $box
        $res = $box.Result
        if ($box.Error -or -not $res) {
            $why = "$($box.Error)"; if (-not $why.Trim()) { $why = 'the stage returned nothing' }
            & $say 'TOOL' $ctx.Stage "Stage failed: $why" 'error'
            [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.Stage -Status 'failed' -Note $why)
            $ctx.Phase = 'idle'; $pbar.Visibility = 'Collapsed'; & $drawChips
            & $askRecovery $ctx.Stage $why      # ask, do not end the run
            return
        }
        if ($res.sheet) { $ctx.Sheet = $res.sheet; try { Set-AgentUsage -Summary $ctx.Sheet.audit } catch {} }
        if ($res.result) { $ctx.Result = $res.result }
        if ($res.run) { $ctx.Run = $res.run }
        # a stage that came back without stamping itself would be picked again forever - never let the flow spin
        $st = Get-AgentStageStatus -Sheet $ctx.Sheet -Id $ctx.Stage
        if (-not $st) {
            [void](Set-AgentStage -Sheet $ctx.Sheet -Id $ctx.Stage -Status 'skipped' -Note 'the stage returned without doing anything')
            $st = 'skipped'
        }
        # WHAT THE AGENT SAYS ABOUT IT, in its own words, before the tool's summary line. Every stage result carries
        # `narration` - one or two sentences as a packager would say them out loud - and that is what belongs in the
        # feed. The tool then adds its own short factual line underneath.
        $nar = ''
        $src = switch ("$($ctx.Stage)") { 'plan' { $ctx.Sheet.plan } 'evaluate' { $ctx.Sheet.decision } 'verify' { $ctx.Sheet.verification } default { $null } }
        if ($src -and "$($src.narration)".Trim()) { $nar = "$($src.narration)".Trim() }
        # what the plan decided, in a line the packager can check at a glance
        if ("$($ctx.Stage)" -eq 'plan' -and $ctx.Sheet.plan -and -not $ctx.Sheet.plan.error) {
            $pl = $ctx.Sheet.plan
            foreach ($q in @(Get-AgentList $pl.questions)) { & $say 'AI' 'plan' "Question for the $(if ("$($q.forWhom)".Trim()) { $q.forWhom } else { 'owner' }): $($q.question)" 'step' }
        }
        if ($nar -and $nar -ne $ctx.LastNarration) { $ctx.LastNarration = $nar; & $say 'AI' $ctx.Stage $nar 'step' }
        $note = "$($ctx.Sheet.stages["$($ctx.Stage)"].note)"
        & $say $(if ($st -eq 'failed') { 'TOOL' } else { 'TOOL' }) $ctx.Stage "$((Get-AgentStageDef -Id $ctx.Stage).Title): $st$(if ($note) { " - $note" })" $(if ($st -eq 'failed') { 'error' } else { 'step' })
        $ctx.Phase = 'idle'
        & $drawChips
        # A STAGE THAT RAN AND FAILED DESERVES THE SAME OFFER AS ONE THAT CRASHED. Recovery used to be offered only
        # when the runspace itself errored, so a verification that completed and reported fix_needed simply ended the
        # run - and the packager was left with no way forward but to start the whole order again. Now it asks.
        if ($st -eq 'failed') {
            & $troubleshootThen $ctx.Stage $(if ($note) { $note } else { 'the stage reported a failure' })
            return
        }
        & $advance
    })
    $ctx.Timer = $timer; $ctx.Window = $win; $ctx.RunButton = $bRun
    $script:LastConsoleWindow = $win
    # Draw the route before anything runs, so an empty window still shows what this is going to do.
    & $drawChips
    $win.add_Loaded({ $timer.Start() })
    $win.add_Closed({ try { $timer.Stop() } catch {}; $ctx.Stop = $true; if ($ctx.Box) { try { Stop-AgentRunspace -Box $ctx.Box } catch {} } })
    [void]$win.ShowDialog()
}


