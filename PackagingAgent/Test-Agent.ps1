##############################################################
# Test-Agent.ps1  -  OFFLINE tests for the Packaging Agent (no API key, no network, no share).
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Agent.ps1
# The Gemini transport is replaced by a recorded double; documents are generated on the fly.
##############################################################
$here = Split-Path -Parent $MyInvocation.MyCommand.Path            # PackagingAgent\
$tool = Join-Path (Split-Path -Parent $here) 'MTB-PackageAssistance'   # the brand tool whose engines the agent drives
foreach ($f in 'Core.ps1','Predecessor.ps1','Build.ps1','Source.ps1','MstBuilder.ps1','BundledMsi.ps1','Snapshot.ps1','Screenshots.ps1','PSADT_V3toV4_Mappings.ps1') { . "$tool\$f" }
foreach ($f in 'Agent.Gemini.ps1','Agent.Docs.ps1','Agent.Core.ps1','Agent.App.ps1') { . "$here\$f" }
$script:AgentRoot = $here; $script:AgentToolRoot = $tool
$script:Settings = @{ WorkRoot = (Join-Path $env:TEMP 'PackagingAgentTest'); AI = @{ Enabled = $true; Model = 'gemini-3.5-flash-lite'; MaxCostPerPackageUSD = 5; SendScreenshots = $true } }
$script:WorkRoot = $null
Initialize-Log
$fail = 0
function Assert($name, $cond) { if ($cond) { Write-Host "PASS $name" -ForegroundColor Green } else { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ } }

# ---- helpers: fake Gemini responses ---------------------------------------------------------------------------------
function New-FakeResponse { param([string]$Call, $CallArgs, [string]$Text)
    $parts = @(); if ($Text) { $parts += @{ text = $Text } }; if ($Call) { $parts += @{ functionCall = @{ name = $Call; args = $CallArgs } } }
    return ((@{ candidates = @(@{ content = @{ role = 'model'; parts = $parts }; finishReason = 'STOP' }); usageMetadata = @{ promptTokenCount = 1000; candidatesTokenCount = 200; totalTokenCount = 1200 } } | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
}
$script:FakeLog = New-Object System.Collections.Generic.List[object]
$script:PkgAgent.Transport = {
    param($Body, $Model, $Name)
    $script:FakeLog.Add(@{ Name = $Name; Body = $Body })
    $last = @($Body.contents)[-1]
    $hasFnResp = [bool](@($last.parts) | Where-Object { $_ -is [hashtable] -and $_.ContainsKey('functionResponse') })
    switch -regex ($Name) {
        '^connection' { return (New-FakeResponse -Text 'OK') }
        '^extract'    { return (New-FakeResponse -Call 'submit_form_extraction' -CallArgs @{ formVersion = 'v2.0'; product = @{ vendor = 'Irfan Skiljan'; name = 'IrfanView'; version = '4.75'; arch = 'x64'; distribution = @('SCCM'); minorUpdate = 'no' }
                                                            installMethod = @{ silentCommandFromForm = '/silent /folder="C:\Program Files\IrfanView" /allusers=1'; needsResponseFile = $false; parametersMentioned = @('/silent', '/allusers=1') }
                                                            wizardSteps = @(@{ step = 1; screen = 'Welcome'; whatAOChose = 'Next'; deviatesFromDefault = $false }); prerequisites = @{ predecessorMustBeRemoved = $true }; licensing = @{ required = $true; type = 'Single'; notes = 'user buys' }; unclearOrContradictory = @(); emptyButNeeded = @('detailed description') }) }
        '^decide'     { if ($hasFnResp) { return (New-FakeResponse -Call 'submit_assessment' -CallArgs @{ readiness = 'ready'; blockers = @(); questionsForAO = @()
                                                            packagingMethod = @{ method = 'EXE-silent'; reason = 'vendor documents /silent'; installCandidates = @(@{ installer = 'setup.exe'; command = '/silent /allusers=1'; uninstall = 'iv_uninstall.exe /silent'; source = 'form'; confidence = 'high'; note = '' }); expectedSilent = $true; autoUpdateHandling = 'none known'; perUserConfigExpected = $true; detectionSuggestion = 'ARP DisplayVersion' }
                                                            snapshotPlan = @{ runAs = 'Admin'; installerToRun = 'setup.exe'; argsToRun = '/silent /allusers=1'; whatToWatch = @('ARP entry', 'desktop shortcut'); expectedArpName = 'IrfanView 4.75 (64-bit)' }; fastLane = $false; risks = @(); summaryForPackager = 'Simple EXE, silent switch documented.' }) }
                        return (New-FakeResponse -Call 'knowledge_base_lookup' -CallArgs @{ vendor = 'IrfanSkiljan'; app = 'IrfanView'; engine = 'unknown'; installerName = 'setup.exe' }) }
        '^classify'   { return (New-FakeResponse -Call 'submit_decision' -CallArgs @{ installOutcome = @{ silent = $true; exitCodeOk = $true; installedAsExpected = $true; notes = '' }
                                                            items = @(@{ category = 'Tasks'; label = 'IrfanUpdater'; verdict = 'auto-update'; action = 'remove'; reason = 'vendor updater'; command = "Unregister-ScheduledTask -TaskName 'IrfanUpdater' -Confirm:`$false" }, @{ category = 'Programs'; label = 'IrfanView 4.75 (64-bit)'; verdict = 'app-core'; action = 'keep'; reason = 'the app' })
                                                            autoUpdate = @{ found = $true; mechanism = 'scheduled task'; disableAction = 'remove the task'; commands = @("Unregister-ScheduledTask -TaskName 'IrfanUpdater' -Confirm:`$false") }
                                                            perUser = @{ needed = $true; mode = 'ActiveSetup'; what = 'ini in APPDATA' }; uninstall = @{ command = 'C:\Program Files\IrfanView\iv_uninstall.exe'; silentArgs = '/silent'; fromArp = $true }
                                                            detection = @{ type = 'Registry DisplayVersion'; key = 'HKLM:\...\IrfanView64'; value = '4.75' }
                                                            packagingMethod = @{ method = 'EXE-silent'; installCommand = 'setup.exe /silent /allusers=1'; uninstallCommand = 'iv_uninstall.exe /silent'; reason = 'proven silent'; changedFromProposal = $false }
                                                            preInstall = @(); postInstall = @('remove desktop shortcut'); postUninstallCleanup = @(); needsHumanDecision = @('keep thumbnails shortcut?'); confidence = 'high'; summary = 'done' }) }
        default       { return (New-FakeResponse -Text 'no idea') }
    }
}

# ---- 1. Gemini client ---------------------------------------------------------------------------------------------
Reset-AgentUsage
$r = Invoke-GeminiChat -Contents @(@{ role = 'user'; parts = @(@{ text = 'hi' }) }) -Name 'connection-test'
Assert 'chat: text parsed'                 ($r.Text -eq 'OK')
Assert 'chat: usage + cost accounted'      ($script:PkgAgent.Calls -eq 1 -and $script:PkgAgent.TokensIn -eq 1000 -and $script:PkgAgent.CostUSD -gt 0)
Assert 'chat: audit file written'          ((Get-ChildItem (Get-AgentAuditDir) -Filter '*.json').Count -ge 1)
$t = Test-GeminiConnection
Assert 'connection test ok'                ($t.Ok)
$parts = @{ contents = @(@{ role = 'user'; parts = @(@{ text = 'x' }, @{ inlineData = @{ mimeType = 'image/png'; data = ('A' * 5000) } }) }) }
$safe = ConvertTo-AgentAuditSafe $parts
Assert 'audit: image bytes replaced'       ("$($safe.contents[0].parts[1].inlineData.data)" -match '^<5000 base64')
Assert 'config: model default'             ((Get-AgentModel) -eq 'gemini-3.5-flash-lite')
Assert 'key: none without env/session'     (-not $script:PkgAgent.ApiKey)

# ---- 1b. OpenAI-compatible gateway: shape conversion (no network) --------------------------------------------------------
$conv = @(
    @{ role = 'user'; parts = @(@{ text = 'hello' }, @{ inlineData = @{ mimeType = 'image/png'; data = 'AAAA' } }) },
    @{ role = 'model'; parts = @(@{ text = 'sure' }, @{ functionCall = @{ name = 'read_document'; args = @{ path = 'a.txt' } }; id = 'call_1' }) },
    @{ role = 'user'; parts = @(@{ functionResponse = @{ name = 'read_document'; response = @{ text = 'content' } } }) })
$m = ConvertTo-OpenAIMessages -System 'sys' -Contents $conv
Assert 'openai: system + user(text+image) + assistant(tool_calls) + tool' ($m.Count -eq 4 -and $m[0].role -eq 'system' -and $m[1].content[1].type -eq 'image_url' -and $m[2].tool_calls[0].id -eq 'call_1' -and $m[3].role -eq 'tool' -and $m[3].tool_call_id -eq 'call_1')
$sc = ConvertTo-OpenAISchema (Get-AgentSchema 'submit_assessment')
Assert 'openai: schema types lowercased'  ($sc.type -eq 'object' -and $sc.properties.questionsForAO.type -eq 'array' -and $sc.properties.questionsForAO.items.type -eq 'object')
$script:PkgAgent.Overrides = @{ BaseUrl = 'https://gateway.example/v1'; Provider = 'openai'; Model = 'gemini-2.5-flash-lite' }
Assert 'openai: runtime overrides win'    ((Get-AgentProvider) -eq 'openai' -and (Get-AgentModel) -eq 'gemini-2.5-flash-lite' -and (Get-AgentConfig).BaseUrl -eq 'https://gateway.example/v1')
$script:PkgAgent.Overrides = $null
Assert 'gemini: default provider'         ((Get-AgentProvider) -eq 'gemini')

# ---- 2. tool loop -----------------------------------------------------------------------------------------------------
$tmp = Join-Path $env:TEMP ('PackagingAgentTest\order_' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$script:FakeLog.Clear()
$res = Invoke-AgentTask -Task 'decide' -Instruction 'test' -Parts @(@{ text = 'facts' }) -SubmitName 'submit_assessment' -ReadTools (Get-AgentReadTools -OrderFolder $tmp)
Assert 'task: read tool dispatched then submit'   ($script:FakeLog.Count -eq 2 -and $res.readiness -eq 'ready')
$fr = @($script:FakeLog[1].Body.contents)[-1].parts[0].functionResponse
Assert 'task: function response carries KB result' ($fr.name -eq 'knowledge_base_lookup' -and $fr.response.ContainsKey('found'))
Assert 'task: model turn kept verbatim'            (@($script:FakeLog[1].Body.contents)[1].role -eq 'model')
$rt = Get-AgentReadTools -OrderFolder $tmp
$rd = & ($rt | Where-Object { $_.Decl.name -eq 'read_document' }).Run @{ path = '..\..\outside.txt' } $rt[0].Ctx
Assert 'read tool: path outside order refused'     ($rd.error)

# ---- 3. scrub -----------------------------------------------------------------------------------------------------------
$s = Invoke-AgentScrub "Email | nikhil.x@man.eu`nPhone | 091 9860 348 680`nLast Name | Pandhare`nVersion 4.75.0.0 date 19/09/2026 RITM0711780"
Assert 'scrub: email/phone/name redacted'  ($s -notmatch 'man\.eu|9860|Pandhare')
Assert 'scrub: version/date/RITM kept'     ($s -match '4\.75\.0\.0' -and $s -match '19/09/2026' -and $s -match 'RITM0711780')

# ---- 4. docx / xlsx readers on generated files ---------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-TestZip { param($Path, [hashtable]$Entries) if (Test-Path $Path) { Remove-Item $Path -Force }; $z = [IO.Compression.ZipFile]::Open($Path, 'Create'); try { foreach ($k in $Entries.Keys) { $e = $z.CreateEntry($k); $w = New-Object IO.StreamWriter($e.Open(), (New-Object Text.UTF8Encoding $false)); $w.Write($Entries[$k]); $w.Close() } } finally { $z.Dispose() } }
$ct = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
$rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
$w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$docXml = @"
<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="$w"><w:body>
<w:p><w:r><w:t>Software Package Request</w:t></w:r></w:p>
<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Manufacturer</w:t></w:r></w:p></w:tc><w:sdt><w:sdtContent><w:tc><w:p><w:r><w:t>Irfan Skiljan</w:t></w:r></w:p></w:tc></w:sdtContent></w:sdt></w:tr>
<w:tr><w:tc><w:p><w:r><w:t>Package ID</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>RITM0711780</w:t></w:r></w:p></w:tc></w:tr>
<w:tr><w:tc><w:p><w:r><w:t>Distribution Behaviour</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>&#x2612;SCCM / &#x2610;Intune</w:t></w:r></w:p></w:tc></w:tr>
<w:tr><w:tc><w:p><w:r><w:t>SW Architecture</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>&#x2610; x86 / &#x2612;x64 / &#x2610;All</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r><w:t>Installation Instructions</w:t></w:r></w:p><w:p><w:r><w:t>setup.exe /silent</w:t></w:r></w:p>
<w:p><w:r><w:t>&#x2612;   Any previous version of this software(Predecessor):</w:t></w:r></w:p>
</w:body></w:document>
"@
$docx = Join-Path $tmp 'Installation instructions for MAN Test.docx'
New-TestZip -Path $docx -Entries @{ '[Content_Types].xml' = $ct; '_rels/.rels' = $rels; 'word/document.xml' = $docXml }
$d = Read-AgentDocx -Path $docx
Assert 'docx: readable'                    ($d.Ok -and $d.Blocks.Count -ge 4)
Assert 'docx: sdt-wrapped cell value read' ($d.Text -match 'Manufacturer \| Irfan Skiljan')
Assert 'docx: checkbox glyphs kept'        ($d.Text -match ([string][char]0x2612 + 'SCCM'))
$ssXml = '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2"><si><t>Task</t></si><si><t>Repackaging necessary?</t></si></sst>'
$sheetXml = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1"><v>5</v></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>inline</t></is></c></row></sheetData></worksheet>'
$xct = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>'
$xlsx = Join-Path $tmp 'Complexity_Matrix_Test.xlsx'
New-TestZip -Path $xlsx -Entries @{ '[Content_Types].xml' = $xct; '_rels/.rels' = $rels; 'xl/sharedStrings.xml' = $ssXml; 'xl/worksheets/sheet1.xml' = $sheetXml }
$x = Read-AgentXlsx -Path $xlsx
Assert 'xlsx: shared + inline strings + numbers' ($x.Ok -and $x.Sheets[0].Rows[0][1] -eq 'Repackaging necessary?' -and $x.Sheets[0].Rows[0][2] -eq '5' -and $x.Sheets[0].Rows[1][0] -eq 'inline')

# ---- 5. intake without model (rules) --------------------------------------------------------------------------------------
'RITM' | Out-File (Join-Path $tmp 'RITM0711780.txt')
[IO.File]::WriteAllBytes((Join-Path $tmp 'setup.exe'), [byte[]](0x4D, 0x5A) + [byte[]](1..200))
$docs = Find-AgentOrderDocs -Folder $tmp
Assert 'order docs: form / complexity / ritm found' ($docs.Form -eq $docx -and $docs.Complexity -eq $xlsx -and $docs.Ritm -eq 'RITM0711780')
$sheet = Invoke-AgentIntake -Folder $tmp -PkgName 'IrfanSkiljan_IrfanView_x64_4.75-0001_MUL' -NoModel -SkipPredecessor
Assert 'intake: identity parsed'             ($sheet.identity.parsedOk -and $sheet.identity.vendor -eq 'IrfanSkiljan')
Assert 'intake: installer fingerprinted'     ($sheet.sources.allInstallerCount -eq 1 -and $sheet.sources.installers[0].name -eq 'setup.exe')
Assert 'intake: rule fields from form'       ($sheet.declared.fromRules.distribution -contains 'SCCM' -and $sheet.declared.fromRules.archTicked -eq 'x64' -and $sheet.declared.fromRules.removePredecessorTicked)
Assert 'intake: status ready (no model)'     ($sheet.status -eq 'ready')
Assert 'intake: sheet saved (json + html)'   ((Test-Path (Join-Path (Get-AgentSheetDir $sheet) 'evaluation-sheet.json')) -and (Test-Path (Join-Path (Get-AgentSheetDir $sheet) 'evaluation-sheet.html')))
$empty = Join-Path $env:TEMP ('PackagingAgentTest\empty_' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force -Path $empty | Out-Null
$sheetE = Invoke-AgentIntake -Folder $empty -PkgName 'Bad Name' -NoModel -SkipPredecessor
Assert 'intake: empty order -> blocked (no installer, no form)' ($sheetE.status -eq 'blocked' -and @($sheetE.gaps | Where-Object { $_.id -eq 'SRC-NOINSTALLER' }).Count -eq 1 -and @($sheetE.gaps | Where-Object { $_.id -eq 'DOC-NOFORM' }).Count -eq 1)
Assert 'text render works on blocked sheet'  ((Format-AgentSheetText $sheetE) -match 'BLOCKED')

# ---- 6. intake with the (fake) model -------------------------------------------------------------------------------------
$script:PkgAgent.ApiKey = 'fake'
$sheetM = Invoke-AgentIntake -Folder $tmp -PkgName 'IrfanSkiljan_IrfanView_x64_4.75-0001_MUL' -SkipPredecessor
Assert 'intake+model: extraction merged'     ($sheetM.declared.installMethod.silentCommandFromForm -match '/silent')
Assert 'intake+model: assessment stored'     ($sheetM.assessment.readiness -eq 'ready' -and $sheetM.assessment.packagingMethod.method -eq 'EXE-silent')
Assert 'intake+model: status ready'          ($sheetM.status -eq 'ready')
$prop = Get-AgentRunProposal -Sheet $sheetM
Assert 'run proposal: args from snapshot plan' ($prop.Args -eq '/silent /allusers=1' -and $prop.RunAs -eq 'Admin' -and $prop.Name -eq 'setup.exe')
Assert 'html: renders the model sections'    ((ConvertTo-AgentSheetHtml $sheetM) -match 'Proposed packaging method' -and (ConvertTo-AgentSheetHtml $sheetM) -match '/silent /allusers=1')

# ---- 7. snapshot decision on a synthetic analyzer result ------------------------------------------------------------------
$diff = [ordered]@{ Programs = @{ Added = @([pscustomobject]@{ Id = 'HKLM:\...\IrfanView64'; Info = @{ DisplayName = 'IrfanView 4.75 (64-bit)'; DisplayVersion = '4.75'; Publisher = 'Irfan Skiljan'; UninstallString = '"C:\Program Files\IrfanView\iv_uninstall.exe"' } }); Noise = @() }
                    Tasks = @{ Added = @([pscustomobject]@{ Id = '\IrfanUpdater'; Info = @{ Name = 'IrfanUpdater'; Path = '\'; Action = 'upd.exe' } }); Noise = @() } }
$cs = [ordered]@{ App = 'IrfanView'; When = ''; Counts = @{ new = 3; modified = 0; deleted = 0 }; Files = @(@{ Path = 'C:\Program Files\IrfanView\i_view64.exe'; Change = 'new' }); Registry = @(@{ Path = 'HKLM\SOFTWARE\IrfanView'; Change = 'new' }); RegValues = @{ 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' = @(@{ Name = 'IV'; New = 'x.exe' }) }; Lists = @{}; Env = @(); Noise = @() }
$result = @{ Diff = $diff; ChangeSet = $cs; Un = @{ DisplayName = 'IrfanView 4.75 (64-bit)'; DisplayVersion = '4.75'; ProductCode = ''; Uninstall = '"C:\Program Files\IrfanView\iv_uninstall.exe" /silent' }; Hkcu = @('HKCU:\Software\IrfanView'); UserFiles = @(); Cleanups = @([pscustomobject]@{ Kind = 'Task'; Default = $true; Label = 'Remove scheduled task: IrfanUpdater'; Command = "Unregister-ScheduledTask -TaskName 'IrfanUpdater' -TaskPath '\' -Confirm:`$false -ErrorAction SilentlyContinue"; Note = '' }); Shortcuts = @(); ReportText = 'report'; LeftoverCandidates = $null; FileDiff = @{ InstalledBytes = 5MB } }
$sum = ConvertTo-AgentSnapshotSummary -Result $result
Assert 'summary: programs + tasks + file groups + run values' ($sum.Programs.addedCount -eq 1 -and $sum.Tasks.addedCount -eq 1 -and $sum.fileGroups.Count -eq 1 -and $sum.registryValuesSample.Count -eq 1)
$run = @{ Installer = (Join-Path $tmp 'setup.exe'); Args = '/silent'; RunAs = 'Admin'; ExitCode = 0; DurationSec = 12; WindowsSeen = @(); TimedOut = $false; Error = ''; Command = 'setup.exe /silent' }
$sheetM = Invoke-AgentSnapshotDecision -Sheet $sheetM -Result $result -RunInfo $run
Assert 'decision: stored + status evaluated' ($sheetM.status -eq 'evaluated' -and $sheetM.decision.packagingMethod.installCommand -eq 'setup.exe /silent /allusers=1' -and $sheetM.observed.run.ExitCode -eq 0)
Assert 'decision: text + html render'        ((Format-AgentSheetText $sheetM) -match 'DECISION' -and (ConvertTo-AgentSheetHtml $sheetM) -match 'Decision after snapshot')

# ---- 8. UI helpers (no window) ---------------------------------------------------------------------------------------------
Assert 'args-only: strips exe name'          ((Get-AgentArgsOnly -Command 'setup.exe /silent /allusers=1' -InstallerName 'setup.exe') -eq '/silent /allusers=1')
Assert 'args-only: strips quoted path'       ((Get-AgentArgsOnly -Command '"C:\src\Setup Foo.exe" /S' -InstallerName 'Setup Foo.exe') -eq '/S')
Assert 'args-only: msiexec /i form'          ((Get-AgentArgsOnly -Command 'msiexec /i "app.msi" /qn REBOOT=ReallySuppress' -InstallerName 'app.msi') -eq '/qn REBOOT=ReallySuppress')
Assert 'args-only: bare args untouched'      ((Get-AgentArgsOnly -Command '/VERYSILENT /NORESTART' -InstallerName 'x.exe') -eq '/VERYSILENT /NORESTART')

# ---- 9. standalone: no agent code inside the tool; export writes the handover files ---------------------------------------
Assert 'tool folder has NO agent files'       (-not (Get-ChildItem "$tool" -Filter 'Agent*.ps1'))
Assert 'tool GUI/pack untouched by the agent'  (((Get-Content "$tool\GUI.ps1" -Raw) -notmatch 'BtnAssistant|Agent\.Core') -and ((Get-Content "$tool\Pack-Engine.ps1" -Raw) -notmatch 'Agent\.'))
$ctxE = @{ Sheet = $sheetM; Result = $result; RunInfo = $run }
$exp = Export-AgentEvaluation -Ctx $ctxE
Assert 'export: sheet + snapshot report + handover written' ((Test-Path $exp.Sheet) -and (Test-Path $exp.SnapshotReport) -and (Test-Path $exp.Handover))
$ho = Get-Content $exp.Handover -Raw | ConvertFrom-Json
Assert 'export: handover carries args + cleanup'  ($ho.installArgs -eq '/silent /allusers=1' -and @($ho.cleanupCommands).Count -ge 1 -and $ho.uninstallFromArp -match 'iv_uninstall')
$snap = Read-SnapshotState -Path $exp.SnapshotReport
Assert 'export: snapshot report loadable by the tool' ($snap -and "$($snap.Uninstall)" -match 'iv_uninstall' -and @($snap.Exclusions).Count -ge 1)
foreach ($f in 'Agent.Gemini.ps1','Agent.Docs.ps1','Agent.Core.ps1','Agent.App.ps1','Start-PackagingAgent.ps1') { $b = [IO.File]::ReadAllBytes("$here\$f"); Assert "$f has UTF-8 BOM" ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }

try { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $empty -Recurse -Force -ErrorAction SilentlyContinue } catch {}
if ($fail) { Write-Host "`n$fail TEST(S) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "`nALL AGENT TESTS PASSED" -ForegroundColor Green }
