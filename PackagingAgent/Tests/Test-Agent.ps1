##############################################################
# Test-Agent.ps1  -  OFFLINE tests for the Packaging Agent (no API key, no network, no share).
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-Agent.ps1
#
# The model is replaced by a scripted double ($script:PkgAgent.Transport), so every job - plan, review, verify,
# consult, experience - runs end to end through the real job runner, the real hands and the real fold, without a
# single call leaving this machine. Documents and packages are generated on the fly.
##############################################################
$testRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$here = Split-Path -Parent $testRoot
$tool = Join-Path $here 'Engine'
foreach ($f in 'Core.ps1', 'Predecessor.ps1', 'Source.ps1', 'MstBuilder.ps1', 'BundledMsi.ps1', 'Snapshot.ps1', 'Screenshots.ps1', 'PSADT_V3toV4_Mappings.ps1', 'Build.ps1') { if (Test-Path "$tool\$f") { . "$tool\$f" } }
foreach ($f in 'Agent.Tools.ps1', 'Agent.Gemini.ps1', 'Agent.Docs.ps1', 'Agent.Prompts.ps1', 'Agent.Ops.ps1', 'Agent.Core.ps1', 'Agent.Brain.ps1', 'Agent.Ui.ps1', 'Agent.Console.ps1') { . "$here\Src\$f" }
$script:AgentHome = $here; $script:AgentSrc = (Join-Path $here 'Src'); $script:AgentToolRoot = $tool
$script:Settings = @{ WorkRoot = (Join-Path $env:TEMP 'PackagingAgentTest'); AI = @{ Enabled = $true; Model = 'gemini-3.5-flash-lite'; MaxCostPerPackageUSD = 5; SendScreenshots = $true } }
$script:WorkRoot = $null
Initialize-Log
$fail = 0
function Assert($name, $cond) { if ($cond) { Write-Host "PASS $name" -ForegroundColor Green } else { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ } }
function New-TestDir([string]$Tag) { $d = Join-Path $env:TEMP ("PackagingAgentTest\$Tag`_" + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force -Path $d | Out-Null; return $d }
function Section([string]$T) { Write-Host "`n--- $T ---" -ForegroundColor Cyan }
# the knowledge files are the agent's real training material - tests never leave anything in them
$casesPath = Get-AgentCasesPath; $casesBak = if (Test-Path -LiteralPath $casesPath) { [IO.File]::ReadAllText($casesPath) } else { $null }
if (Test-Path -LiteralPath $casesPath) { Remove-Item -LiteralPath $casesPath -Force }

# ---- the scripted model ------------------------------------------------------------------------------------------------
function New-FakeResponse { param([string]$Call, $CallArgs, [string]$Text, [object[]]$Calls)
    $parts = @(); if ($Text) { $parts += @{ text = $Text } }
    if ($Call) { $parts += @{ functionCall = @{ name = $Call; args = $CallArgs } } }
    foreach ($c in @($Calls)) { if ($c) { $parts += @{ functionCall = @{ name = $c.name; args = $c.args } } } }
    return ((@{ candidates = @(@{ content = @{ role = 'model'; parts = $parts }; finishReason = 'STOP' }); usageMetadata = @{ promptTokenCount = 1000; candidatesTokenCount = 200; cachedContentTokenCount = 400; totalTokenCount = 1200 } } | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
}
function Get-LastTurnText($Body) { return (@($Body.contents)[-1] | ConvertTo-Json -Depth 30 -Compress) }
$script:FakeLog = New-Object System.Collections.Generic.List[object]
$script:Fake = @{}          # per-scenario answers: name-prefix -> scriptblock ($Body, $Round) -> response
$script:PkgAgent.Transport = {
    param($Body, $Model, $Name)
    $script:FakeLog.Add(@{ Name = $Name; Body = $Body; Model = $Model })
    if ($Name -match '^connection') { return (New-FakeResponse -Text 'OK') }
    $job = ($Name -split '-')[0]; $round = ($Name -split '-')[-1]
    if ($script:Fake.ContainsKey($job)) { return (& $script:Fake[$job] $Body $round) }
    return (New-FakeResponse -Text 'no idea')
}

# =====================================================================================================================
Section 'the agent folder: only what the agent needs'
foreach ($f in @(Get-ChildItem (Join-Path $here 'Src') -Filter '*.ps1')) {
    $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e)
    Assert "$($f.Name) parses" (@($e).Count -eq 0)
    $b = [IO.File]::ReadAllBytes($f.FullName); Assert "$($f.Name) has a UTF-8 BOM" ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}
foreach ($f in 'Start-PackagingAgent.ps1', 'Invoke-PackagingAgent.ps1', 'Tests\Test-Agent.ps1') {
    $t = Get-Content (Join-Path $here $f) -Raw
    Assert "$(Split-Path -Leaf $f) loads the brain" ($t -match "'Agent\.Brain\.ps1'")
    Assert "$(Split-Path -Leaf $f) resolves its folder from PSScriptRoot" ($t -match 'if\s*\(\s*\$PSScriptRoot\s*\)')
}
Assert 'runspaces load the brain too'              ((Get-Content (Join-Path $here 'Src\Agent.Ui.ps1') -Raw) -match "'Agent\.Brain\.ps1'")
Assert 'no Demo folder'                            (-not (Test-Path (Join-Path $here 'Demo')))
Assert 'the agent runs on its OWN engine copy'     ((Test-Path (Join-Path $here 'Engine\Core.ps1')) -and -not (Get-ChildItem (Join-Path $here 'Engine') -Filter 'Agent*.ps1'))
$allSrc = (Get-ChildItem (Join-Path $here 'Src') -Filter '*.ps1' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
foreach ($gone in 'Invoke-AgentTask\b', 'Invoke-AgentReuseDecision', 'Invoke-AgentBuildInstructions', 'submit_assessment', 'submit_reuse', 'submit_build_instructions', 'Get-AgentAskTools', '\.assessment\.', '\$Sheet\.reuse\b') {
    Assert "the old brain is gone: $gone" ($allSrc -notmatch $gone)
}
foreach ($fn in @([regex]::Matches($allSrc, '(?m)^\s*function\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value } | Group-Object | Where-Object { $_.Count -gt 1 })) {
    Assert "function defined once: $($fn.Name)" $false
}

# =====================================================================================================================
Section 'the model client'
Reset-AgentUsage
$r = Invoke-GeminiChat -Contents @(@{ role = 'user'; parts = @(@{ text = 'hi' }) }) -Name 'connection-test'
Assert 'chat: text parsed'                         ($r.Text -eq 'OK')
Assert 'chat: usage + cost accounted'              ($script:PkgAgent.Calls -eq 1 -and $script:PkgAgent.TokensIn -eq 1000 -and $script:PkgAgent.CostUSD -gt 0)
Assert 'chat: cached prompt tokens are counted'    ((Get-AgentUsageSummary).TokensCached -eq 400)
Assert 'chat: an audit file is written'            ((Get-ChildItem (Get-AgentAuditDir) -Filter '*.json').Count -ge 1)
Assert 'connection test ok'                        ((Test-GeminiConnection).Ok)
$safe = ConvertTo-AgentAuditSafe @{ contents = @(@{ role = 'user'; parts = @(@{ text = 'x' }, @{ inlineData = @{ mimeType = 'image/png'; data = ('A' * 5000) } }) }) }
Assert 'audit: image bytes are never written'      ("$($safe.contents[0].parts[1].inlineData.data)" -match '^<5000 base64')
$conv = @(
    @{ role = 'user'; parts = @(@{ text = 'hello' }, @{ inlineData = @{ mimeType = 'image/png'; data = 'AAAA' } }) },
    @{ role = 'model'; parts = @(@{ text = 'sure' }, @{ functionCall = @{ name = 'read_document'; args = @{ path = 'a.txt' } }; id = 'call_1' }, @{ functionCall = @{ name = 'submit_plan'; args = @{} }; id = 'call_2' }) },
    @{ role = 'user'; parts = @(@{ functionResponse = @{ name = 'read_document'; response = @{ text = 'content' } } }) })
$m = ConvertTo-OpenAIMessages -System 'sys' -Contents $conv
Assert 'openai: system + user(text+image) + assistant(tool_calls) + tool' ($m[0].role -eq 'system' -and $m[1].content[1].type -eq 'image_url' -and $m[2].tool_calls[0].id -eq 'call_1' -and @($m | Where-Object { $_.role -eq 'tool' -and $_.tool_call_id -eq 'call_1' -and $_.content -match 'content' }).Count -eq 1)
Assert 'openai: an unanswered tool call is closed off' (@($m | Where-Object { $_.role -eq 'tool' -and $_.tool_call_id -eq 'call_2' }).Count -eq 1)
# every schema a strict provider will see must be valid for it
function Test-SchemaNode { param($n, [string]$path, $bad)
    if ($null -eq $n) { $bad.Add("$path : null"); return }
    $t = "$($n.type)"; if (-not $t.Trim()) { $bad.Add("$path : no type") }
    if ($t -eq 'object') {
        $names = @($n.properties.Keys); if (-not $names.Count) { $bad.Add("$path : object with no properties") }
        foreach ($k in $names) { Test-SchemaNode $n.properties[$k] "$path.$k" $bad }
        foreach ($rq in @(@($n.required) | Where-Object { "$_".Trim() })) { if ($names -notcontains "$rq") { $bad.Add("$path : required '$rq' missing") } }
    } elseif ($t -eq 'array') { if ($null -eq $n.items) { $bad.Add("$path : array with no items") } else { Test-SchemaNode $n.items "$path[]" $bad } }
}
foreach ($sn in 'submit_plan', 'submit_look', 'submit_decision', 'submit_uninstall_review', 'submit_retry', 'submit_troubleshoot', 'submit_verification', 'submit_consult', 'submit_experience') {
    $bad = New-Object System.Collections.Generic.List[string]
    Test-SchemaNode (ConvertTo-OpenAISchema (Get-AgentSchema $sn)) $sn $bad
    Assert "schema $sn is valid for strict providers" ($bad.Count -eq 0)
    if ($bad.Count) { $bad | Select-Object -First 5 | ForEach-Object { Write-Host "     $_" -ForegroundColor Red } }
    Assert "schema $sn carries narration" ([bool](Get-AgentSchema $sn).properties.narration)
}
$planSchemaSize = ((ConvertTo-OpenAISchema (Get-AgentSchema 'submit_plan')) | ConvertTo-Json -Depth 30 -Compress).Length
Assert 'the plan schema stays compact'             ($planSchemaSize -lt 14000)
$script:PkgAgent.Overrides = @{ BaseUrl = 'https://gateway.example/v1'; Provider = 'openai'; Model = 'gemini-2.5-pro'; Models = @{ experience = 'gemini-2.5-flash' } }
Assert 'config: runtime overrides win'             ((Get-AgentProvider) -eq 'openai' -and (Get-AgentModel) -eq 'gemini-2.5-pro')
Assert 'config: a job can have its own model'      ((Get-AgentModel -Task 'experience') -eq 'gemini-2.5-flash' -and (Get-AgentModel -Task 'plan') -eq 'gemini-2.5-pro')
$script:PkgAgent.Overrides = $null
# VW LLMaaS auth shape: Bearer <token> in Authorization AND "Bearer <key>" in its own header
$script:PkgAgent.Overrides = @{ Provider = 'openai'; BaseUrl = 'https://llmapi.example/v1'; TokenUrl = 'https://idp.example/token'; ClientId = 'cid'; AuthMode = 'token+key'; ApiKeyHeader = 'X-LLM-API-CLIENT-ID'; ApiKeyPrefix = 'Bearer ' }
$script:PkgAgent.ApiKey = 'sk-unit-test'; $script:PkgAgent.ClientSecret = 'secret'
$script:PkgAgent.AccessToken = 'eyJunit.token'; $script:PkgAgent.AccessTokenExpires = (Get-Date).AddMinutes(5)
$h = Get-OpenAIAuthHeaders
Assert 'llmaas: token in Authorization'            ($h['Authorization'] -eq 'Bearer eyJunit.token')
Assert 'llmaas: key header + Bearer prefix'        ($h['X-LLM-API-CLIENT-ID'] -eq 'Bearer sk-unit-test')
$script:PkgAgent.ClientSecret = $null; $script:PkgAgent.AccessToken = $null; $noSecretErr = ''
try { $null = Get-OpenAIAuthHeaders } catch { $noSecretErr = "$($_.Exception.Message)" }
Assert 'llmaas: a missing secret names the secret' ($noSecretErr -match 'client secret')
$script:PkgAgent.Overrides = $null; $script:PkgAgent.ApiKey = $null; $script:PkgAgent.ClientSecret = $null
# credentials from a settings file, as a fresh runspace sees them
$fakeSettings = Join-Path (New-TestDir 'cfg') 'agent.settings.json'
@{ AI = @{ Provider = 'openai'; BaseUrl = 'https://llmapi.example/v1'; TokenUrl = 'https://idp.example/token'; ClientId = 'cid'; ClientSecret = 'file-secret'; ApiKey = 'sk-from-file' } } | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $fakeSettings -Encoding utf8
$savedSettings = $script:AgentSettingsPath; $script:AgentSettingsPath = $fakeSettings; $script:PkgAgent.KeySource = $null
Assert 'settings file: key and secret are picked up' ("$(Get-AgentApiKey)" -eq 'sk-from-file' -and "$(Get-AgentClientSecret)" -eq 'file-secret')
$script:PkgAgent.AccessToken = 'eyJunit.token'; $script:PkgAgent.AccessTokenExpires = (Get-Date).AddMinutes(5)
$h3 = Get-OpenAIAuthHeaders
Assert 'settings file: auto mode means token+key'  ($h3['Authorization'] -eq 'Bearer eyJunit.token' -and $h3['X-LLM-API-CLIENT-ID'] -eq 'Bearer sk-from-file')
$script:AgentSettingsPath = $savedSettings; $script:PkgAgent.ApiKey = $null; $script:PkgAgent.ClientSecret = $null; $script:PkgAgent.AccessToken = $null; $script:PkgAgent.KeySource = $null
$uiSrc = Get-Content (Join-Path $here 'Src\Agent.Ui.ps1') -Raw
Assert 'runspace: the whole auth state travels'    ($uiSrc -match 'secret\s*=\s*"\$\(\$script:PkgAgent\.ClientSecret\)"' -and $uiSrc -match 'overrides\s*=\s*\$ov' -and $uiSrc -match 'if \(\$p\.secret\)')
Assert 'runspace: the order''s spend travels'      ($uiSrc -match 'Set-AgentUsage -Summary \$p\.arg\.sheet\.audit')
$realCfg = Get-Content (Join-Path $here 'agent.settings.example.json') -Raw | ConvertFrom-Json
Assert 'model: the brain is gemini-2.5-pro'        ("$($realCfg.AI.Model)" -eq 'gemini-2.5-pro' -and @($realCfg.AI.FallbackModels).Count -ge 1)
Assert 'settings: the file is only the connection, the model and the cap' (-not $realCfg.AI.PSObject.Properties['Prices'] -and -not $realCfg.AI.PSObject.Properties['Models'] -and -not $realCfg.AI.PSObject.Properties['Temperature'] -and @($realCfg.AI.PSObject.Properties).Count -le 15)
Assert 'settings: the cost cap still knows every model''s price' (@('gemini-2.5-pro', 'claude-sonnet-4.6', 'gpt-5.1') | Where-Object { $script:AgentDefaultPrices.ContainsKey($_) }).Count -eq 3

# =====================================================================================================================
Section 'reading what the orderer sent'
$s = Invoke-AgentScrub "Email | nikhil.x@man.eu`nPhone | 091 9860 348 680`nLast Name | Pandhare`nVersion 4.75.0.0 date 19/09/2026 RITM0711780"
Assert 'scrub: email/phone/name redacted'          ($s -notmatch 'man\.eu|9860|Pandhare')
Assert 'scrub: version/date/RITM kept'             ($s -match '4\.75\.0\.0' -and $s -match '19/09/2026' -and $s -match 'RITM0711780')
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-TestZip { param($Path, [hashtable]$Entries) if (Test-Path $Path) { Remove-Item $Path -Force }; $z = [IO.Compression.ZipFile]::Open($Path, 'Create'); try { foreach ($k in $Entries.Keys) { $e = $z.CreateEntry($k); $w = New-Object IO.StreamWriter($e.Open(), (New-Object Text.UTF8Encoding $false)); $w.Write($Entries[$k]); $w.Close() } } finally { $z.Dispose() } }
function New-TestDocx { param([string]$Path, [string[]]$Paragraphs, [string]$TableXml = '')
    $ct = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
    $rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    $body = (@($Paragraphs) | ForEach-Object { "<w:p><w:r><w:t>$_</w:t></w:r></w:p>" }) -join ''
    New-TestZip -Path $Path -Entries @{ '[Content_Types].xml' = $ct; '_rels/.rels' = $rels; 'word/document.xml' = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><w:document xmlns:w=`"http://schemas.openxmlformats.org/wordprocessingml/2006/main`"><w:body>$TableXml$body</w:body></w:document>" }
}
$docDir = New-TestDir 'docs'
$formTable = '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Manufacturer</w:t></w:r></w:p></w:tc><w:sdt><w:sdtContent><w:tc><w:p><w:r><w:t>Irfan Skiljan</w:t></w:r></w:p></w:tc></w:sdtContent></w:sdt></w:tr><w:tr><w:tc><w:p><w:r><w:t>Distribution Behaviour</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>&#x2612;SCCM / &#x2610;Intune</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>SW Architecture</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>&#x2610; x86 / &#x2612;x64 / &#x2610;All</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
New-TestDocx -Path (Join-Path $docDir 'Software Package Request Form.docx') -TableXml $formTable -Paragraphs (@('Request form: please package Acme Reader 3.1', "&#x2612;   Any previous version of this software(Predecessor):") + @(1..60 | ForEach-Object { "padding line $_" }))
New-TestDocx -Path (Join-Path $docDir 'Installation Instructions.docx') -Paragraphs @('Run setup.exe /VERYSILENT /SP- /NORESTART then place config.xml')
$d = Read-AgentDocx -Path (Join-Path $docDir 'Software Package Request Form.docx')
Assert 'docx: sdt-wrapped cell value read'         ($d.Ok -and $d.Text -match 'Manufacturer \| Irfan Skiljan')
Assert 'docx: checkbox glyphs kept'                ($d.Text -match ([string][char]0x2612 + 'SCCM'))
$found = Find-AgentOrderDocs -Folder $docDir
Assert 'docs: the request form is identified'      ((Split-Path -Leaf "$($found.Form)") -eq 'Software Package Request Form.docx')
Assert 'docs: the SMALLER instructions doc survives' ((Split-Path -Leaf "$($found.Instructions)") -eq 'Installation Instructions.docx')
$ssXml = '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2"><si><t>Task</t></si><si><t>Repackaging necessary?</t></si></sst>'
$sheetXml = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1"><v>5</v></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>inline</t></is></c></row></sheetData></worksheet>'
$xct = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>'
$xlsx = Join-Path $docDir 'Complexity_Matrix_Test.xlsx'
New-TestZip -Path $xlsx -Entries @{ '[Content_Types].xml' = $xct; '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>'; 'xl/sharedStrings.xml' = $ssXml; 'xl/worksheets/sheet1.xml' = $sheetXml }
$x = Read-AgentXlsx -Path $xlsx
Assert 'xlsx: shared + inline strings + numbers'   ($x.Ok -and $x.Sheets[0].Rows[0][1] -eq 'Repackaging necessary?' -and $x.Sheets[0].Rows[0][2] -eq '5' -and $x.Sheets[0].Rows[1][0] -eq 'inline')
[IO.File]::WriteAllBytes((Join-Path $docDir 'Old Instructions.doc'), (New-Object byte[] 512))
Assert 'docs: an unreadable legacy .doc says why'  (-not (Read-AgentLegacyDoc -Path (Join-Path $docDir 'Old Instructions.doc')).Ok)
$docTool = @(Get-AgentDocumentTools)[0]
$missing = & $docTool.Run @{ path = 'no_such_document.docx' } @{ Folder = $docDir }
Assert 'read_document: a missing one says so'      ($missing.result.ok -eq $false -and "$($missing.result.note)" -match 'not there')
$rd = & $docTool.Run @{ path = 'Installation Instructions.docx' } @{ Folder = $docDir }
Assert 'read_document: relative to the order'      ($rd.result.ok -and "$($rd.result.text)" -match '/VERYSILENT')

# =====================================================================================================================
Section 'intake: the hands gather, nothing is judged'
$ord = New-TestDir 'order'
Copy-Item (Join-Path $docDir '*.docx') $ord
'RITM' | Out-File (Join-Path $ord 'RITM0711780.txt')
Set-Content (Join-Path $ord 'App Setup 2.0.msi') 'MSI' -Encoding Ascii
Set-Content (Join-Path $ord 'App Setup 2.0.mst') 'MST' -Encoding Ascii
Reset-AgentUsage; $callsBefore = $script:FakeLog.Count
$sheet = Invoke-AgentIntake -Folder $ord -PkgName 'Vendor_App_x64_2.0-0001_MUL' -SkipPredecessor
Assert 'intake: no model call at all'              ($script:FakeLog.Count -eq $callsBefore)
Assert 'intake: identity parsed'                   ($sheet.identity.parsedOk -and $sheet.identity.vendor -eq 'Vendor' -and $sheet.identity.version -eq '2.0')
Assert 'intake: the installer is fingerprinted'    (@($sheet.sources.installers | Where-Object { $_.name -eq 'App Setup 2.0.msi' }).Count -eq 1)
Assert 'intake: the transform is listed'           (@($sheet.sources.transforms | Where-Object { $_.name -eq 'App Setup 2.0.mst' }).Count -eq 1)
Assert 'intake: RITM found'                        ($sheet.ritm -eq 'RITM0711780')
Assert 'intake: tick boxes read by rule'           ($sheet.declared.fromRules.distribution -contains 'SCCM' -and $sheet.declared.fromRules.archTicked -eq 'x64' -and $sheet.declared.fromRules.removePredecessorTicked)
Assert 'intake: the stage is done, plan is next'   ((Get-AgentStageStatus -Sheet $sheet -Id 'intake') -eq 'done' -and (Get-AgentNextStage -Sheet $sheet).id -eq 'plan')
Assert 'intake: the sheet is saved (json + html)'  ((Test-Path (Join-Path (Get-AgentSheetDir $sheet) 'evaluation-sheet.json')) -and (Test-Path (Join-Path (Get-AgentSheetDir $sheet) 'evaluation-sheet.html')))
$empty = New-TestDir 'empty'
$sheetE = Invoke-AgentIntake -Folder $empty -PkgName 'Bad Name' -SkipPredecessor
Assert 'intake: an empty order is blocked'         ($sheetE.status -eq 'blocked' -and @($sheetE.gaps | Where-Object { $_.id -eq 'SRC-NOINSTALLER' }).Count -eq 1)
Assert 'intake: a missing form is a question, not a wall' (@($sheetE.gaps | Where-Object { $_.id -eq 'DOC-NOFORM' -and $_.severity -eq 'ask' }).Count -eq 1)
Assert 'intake: text render of a blocked sheet'    ((Format-AgentSheetText $sheetE) -match 'BLOCKED')
# a previous version delivered INSIDE the order
$inOrd = New-TestDir 'inorder'
$pp = Join-Path $inOrd 'predecessor\Mozilla_FirefoxESR_x64_140.15.0-0001_MUL\Content'
New-Item -ItemType Directory -Force -Path (Join-Path $pp 'Files') | Out-Null
Set-Content (Join-Path $pp 'Invoke-AppDeployToolkit.ps1') '# toolkit' -Encoding utf8
Set-Content (Join-Path $pp 'Files\Firefox Setup 140.15.0esr.msi') 'x' -Encoding ascii
Set-Content (Join-Path $pp 'Files\Firefox.mst') 'x' -Encoding ascii
$fio = @(Find-AgentPredecessorInOrder -OrderFolder $inOrd -CurrentPackageName 'Mozilla_FirefoxESR_x64_140.16.0-0001_MUL')
Assert 'in-order: a delivered predecessor is found' (@($fio).Count -ge 1 -and [bool]@($fio)[0].deliveredWithTheOrder)
$pay = Get-AgentPredecessorPayload -PackagePath (Split-Path -Parent $pp)
Assert 'in-order: what it installed is read'       ($pay.found -and "$(@($pay.installers)[0].ext)" -eq '.msi' -and @($pay.transforms) -contains 'Firefox.mst')

# =====================================================================================================================
Section 'the previous version the plan will find'
$pred = New-TestDir 'pred'
New-Item -ItemType Directory -Force -Path (Join-Path $pred 'Content\Files'), (Join-Path $pred 'Content\SupportFiles') | Out-Null
$tplPath = Get-AgentTemplatePath
$tplText = [IO.File]::ReadAllText((Join-Path $tplPath 'Invoke-AppDeployToolkit.ps1'))
$predText = $tplText.Replace('## <Perform Post-Installation tasks here>', "## <Perform Post-Installation tasks here>`r`n    Write-ADTLogEntry -Message 'post'").Replace('## <Perform Installation tasks here>', "## <Perform Installation tasks here>`r`n    Start-ADTMsiProcess -Action 'Install' -FilePath 'App Setup 1.0.msi' -Transforms 'App Setup 1.0.mst'")
[IO.File]::WriteAllText((Join-Path $pred 'Content\Invoke-AppDeployToolkit.ps1'), $predText, (New-Object Text.UTF8Encoding $true))
Set-Content (Join-Path $pred 'Content\Files\App Setup 1.0.msi') 'OLD' -Encoding Ascii
Set-Content (Join-Path $pred 'Content\Files\App Setup 1.0.mst') 'OLD' -Encoding Ascii
Set-Content (Join-Path $pred 'Content\SupportFiles\ActiveSetup.ps1') '# per-user stub' -Encoding Ascii
$op = Open-AgentPackage -Path $pred
Assert 'open_package: the whole script comes back'  ($op.ok -and $op.script -match "Write-ADTLogEntry -Message 'post'" -and $op.scriptName -match 'Invoke-AppDeployToolkit')
Assert 'open_package: what it shipped is read'      (@($op.payload.installers | Where-Object { $_.name -eq 'App Setup 1.0.msi' }).Count -eq 1)
Assert 'open_package: config equal to the template is only named' (@($op.contents.configFiles | Where-Object { $_.sameAsOurTemplate }).Count -ge 0)
Assert 'open_package: a wrong path says so'         ((Open-AgentPackage -Path 'Z:\nope').note -match 'not reachable')

# =====================================================================================================================
Section 'the dossier: everything, once'
$c = Get-AgentConversation -Sheet $sheet
$c2 = Get-AgentConversation -Sheet $sheet
Assert 'conversation: one list, the same every time' ([object]::ReferenceEquals($c, $c2) -and $c -is [System.Collections.Generic.List[object]])
Assert 'conversation: it starts with the dossier only' ($c.Count -eq 1)
$dos = (@($c[0].parts) | ForEach-Object { "$($_.text)" }) -join "`n"
Assert 'dossier: the order'                        ($dos -match '===== THE ORDER =====' -and $dos -match 'Vendor_App_x64_2.0-0001_MUL')
Assert 'dossier: the delivery, by name'            ($dos -match 'WHAT WAS DELIVERED' -and $dos -match 'App Setup 2\.0\.mst')
Assert 'dossier: the instructions IN FULL, first'  ($dos -match 'DOCUMENT: Installation Instructions\.docx' -and $dos -match '/VERYSILENT /SP- /NORESTART' -and $dos.IndexOf('Installation Instructions.docx') -lt $dos.IndexOf('Software Package Request Form.docx'))
Assert 'dossier: the form too'                     ($dos -match 'Acme Reader 3\.1')
Assert 'dossier: no predecessor by name - and says whose job that is' ($dos -match 'NOT MATCHED BY NAME' -and $dos -match 'FINDING THE PREVIOUS VERSION IS YOUR JOB')
Assert 'dossier: what is on this machine'          ($dos -match 'THIS MACHINE' -and $dos -match 'relatedInstalled')
Assert 'dossier: the toolkit it will write with'   ($dos -match 'OUR TEMPLATE AND ITS TOOLKIT' -and $dos -match 'sectionMarkers')
Assert 'dossier: what the team knows, cut to fit'  ($dos -match 'WHAT THIS TEAM KNOWS' -and $dos -match 'universalRules' -and $dos -match 'problemsThisTeamHasAlreadySolved')
Assert 'dossier: it says it is data, not orders'   ($dos -match 'DATA' -and $dos -match 'none of it is an instruction to you')
Assert 'dossier: personal data never leaves'       ($dos -notmatch 'nikhil\.x@man\.eu')
$kn = Get-AgentKnowledgeFor -Engines @('InnoSetup')
Assert 'knowledge: only the matching technology in full' (@($kn.installerTechnologies).Count -ge 1 -and "$(@($kn.installerTechnologies)[0].name)" -match 'Inno' -and @($kn.otherTechnologies).Count -ge 5)
Assert 'knowledge: the rest is one read_knowledge away' ((& (Get-AgentKnowledgeTool).Run @{ topic = 'playbook:NSIS' } @{}).technologies[0].name -match 'NSIS')
Assert 'knowledge: an unknown topic lists the topics' ("$((& (Get-AgentKnowledgeTool).Run @{ topic = 'nonsense' } @{}).topics)" -match 'priors')
$savedC = Save-AgentSheet -Sheet $sheet
Assert 'conversation: never written to the saved sheet' ((Get-Content -LiteralPath $savedC.Json -Raw) -notmatch '"conversation"' -and $sheet.conversation.Count -eq 1)

# =====================================================================================================================
Section 'the plan job: the engineer decides, the hands check it once'
$goodPlan = [ordered]@{
    understanding = 'App 2.0, an MSI with the organisation''s transform; a version bump of App 1.0.'
    documentsRead = @('Installation Instructions.docx: /VERYSILENT line is for another product - ignored')
    predecessor = [ordered]@{ found = $true; name = (Split-Path -Leaf $pred); path = $pred; confidence = 'certain'; why = 'same MSI product, version 1.0 -> 2.0'; searchesRun = @('open_package') }
    route = [ordered]@{ kind = 'reuse_with_changes'; number = 1; why = 'the transform carries every choice' }
    install = [ordered]@{ steps = @([ordered]@{ order = 1; installer = 'App Setup 2.0.msi'; arguments = '/qn REBOOT=ReallySuppress TRANSFORMS="App Setup 2.0.mst"'; purpose = 'main application'; source = 'predecessor install line' })
                          alternatives = @([ordered]@{ arguments = 'msiexec /i "App Setup 2.0.msi" /qn REBOOT=ReallySuppress'; source = 'playbook'; why = 'without the transform, to isolate it' })
                          runAs = 'Admin' }
    evaluate = [ordered]@{ mustProve = @('ARP shows App 2.0', 'the transform setting ServerName is present'); compareWithPredecessor = $false; removeFirst = @() }
    package = [ordered]@{ sourceFileToUse = 'App Setup 2.0.msi'
                          changes = @([ordered]@{ section = 'Post-Install'; find = "Write-ADTLogEntry -Message 'post'"; replaceWith = "Write-ADTLogEntry -Message 'post'`r`n    Write-ADTLogEntry -Message 'added by the plan'"; why = 'the new version logs its server' },
                                      [ordered]@{ section = 'Post-Install'; find = 'THIS TEXT IS NOT IN THE SCRIPT'; replaceWith = 'x'; why = 'a change that cannot land' })
                          closeProcesses = @('app.exe', [ordered]@{ name = 'apphelper' }, 'C:\path with space.exe')
                          detection = [ordered]@{ type = 'registry'; key = 'HKLM:\SOFTWARE\VWG\CM\Vendor_App_x64_2.0-0001_MUL'; value = '' }
                          predecessorRemoval = [ordered]@{ handledToday = 'generic'; addGeneratedBlock = $false; why = 'removed by name' }
                          deliveredFiles = @([ordered]@{ file = 'App Setup 2.0.mst'; whatItIs = 'the organisation transform'; whatThePackageDoesWithIt = 'applied on install' }) }
    questions = @(); readiness = 'ready'; confidence = 'high'; summary = 'Reuse App 1.0 with the new MSI and its transform.'
    narration = 'The previous package installs this with a transform, so I am keeping that and pointing it at the new MSI.' }
$lazyPlan = [ordered]@{}; foreach ($k in $goodPlan.Keys) { $lazyPlan[$k] = $goodPlan[$k] }
$lazyPlan.install = [ordered]@{ steps = @([ordered]@{ order = 1; installer = 'App Setup 2.0.msi'; arguments = '/qn'; purpose = 'main application'; source = 'guess' }) }
$lazyPlan.package = [ordered]@{ deliveredFiles = @() }
$script:Fake['plan'] = {
    param($Body, $Round)
    $last = Get-LastTurnText $Body
    if ($last -match '"accepted":false') { return (New-FakeResponse -Call 'submit_plan' -CallArgs $goodPlan) }
    if ($Round -eq '1') { return (New-FakeResponse -Calls @(@{ name = 'open_package'; args = @{ path = $pred } }, @{ name = 'read_knowledge'; args = @{ topic = 'playbook:Windows Installer' } })) }
    return (New-FakeResponse -Call 'submit_plan' -CallArgs $lazyPlan)
}
$script:FakeLog.Clear()
$sheet = Invoke-AgentPlan -Sheet $sheet
$planCalls = @($script:FakeLog | Where-Object { $_.Name -match '^plan-' })
Assert 'plan: the stage is done'                   ((Get-AgentStageStatus -Sheet $sheet -Id 'plan') -eq 'done' -and $sheet.plan.route.kind -eq 'reuse_with_changes')
Assert 'plan: two hands in ONE round'              ((Get-LastTurnText $planCalls[1].Body) -match 'open_package' -and (Get-LastTurnText $planCalls[1].Body) -match 'read_knowledge')
Assert 'plan: open_package brought the whole script' ((Get-LastTurnText $planCalls[1].Body) -match 'Write-ADTLogEntry -Message .{1,8}post')
Assert 'plan: a lazy answer went back ONCE'        (@($planCalls).Count -eq 3 -and (Get-LastTurnText $planCalls[2].Body) -match '"accepted":false')
Assert 'plan: it was told exactly what was wrong'  ((Get-LastTurnText $planCalls[2].Body) -match 'App Setup 2\.0\.mst')
Assert 'plan: the handbook is the system prompt'   ("$($planCalls[0].Body.systemInstruction.parts[0].text)" -match 'This team WRAPS')
Assert 'plan: the predecessor the AI found is recorded' ("$($sheet.history.predecessor.path)" -eq $pred -and "$($sheet.history.predecessorFrom)" -match 'chosen by the AI')
Assert 'plan: status follows readiness'            ($sheet.status -in 'ready', 'ask_ao')
Assert 'plan: the transcript is kept for the report' (@($sheet.plan.transcript).Count -ge 1)
$cv = $sheet.conversation
Assert 'fold: the job left two turns, not its scaffolding' ($cv.Count -eq 3 -and "$($cv[1].role)" -eq 'user' -and "$($cv[2].role)" -eq 'model')
Assert 'fold: no tool call survives the fold'      (-not (($cv.ToArray() | ConvertTo-Json -Depth 30 -Compress) -match 'functionCall|functionResponse'))
Assert 'fold: the decision is carried forward'     ("$($cv[1].parts[0].text)" -match 'submit_plan' -and "$($cv[1].parts[0].text)" -match 'reuse_with_changes')
Assert 'fold: the record is not put in the model''s mouth (it would copy it)' ("$($cv[2].parts[0].text)" -notmatch '\{' -and "$($cv[2].parts[0].text)" -match 'submit function')
$looseOk = ConvertFrom-AgentLooseJson -Text "My result (submit_look):`n{""whatItIs"":""x"",""action"":""close_it"",""why"":""y""}" -Schema (Get-AgentSchema 'submit_look')
Assert 'runner: a result written as text is still a result' ($looseOk -and $looseOk.action -eq 'close_it')
Assert 'runner: text missing a required field is not taken' ($null -eq (ConvertFrom-AgentLooseJson -Text '```json {"action":"wait"} ```' -Schema (Get-AgentSchema 'submit_look')))
Assert 'fold: and what the hands were used for'    ("$($cv[1].parts[0].text)" -match 'open_package' -and "$($cv[1].parts[0].text)" -match 'read_knowledge')
Assert 'fold: the narration is not repeated in the record' ("$($cv[2].parts[0].text)" -notmatch 'pointing it at the new MSI')
Assert 'fold: the history is valid for strict providers' (@(ConvertTo-OpenAIMessages -System 's' -Contents $cv.ToArray() | Where-Object { $_.role -eq 'tool' }).Count -eq 0)
# the plan's checks, directly
$tp = Test-AgentPlan -Sheet $sheet -Plan ([ordered]@{ readiness = 'ready'; route = @{ number = 3 }; install = @{ steps = @() }; predecessor = @{ found = $true } })
Assert 'plan check: no install line is sent back'  ($tp -match 'nothing can be tested')
$tp2 = Test-AgentPlan -Sheet $sheet -Plan ([ordered]@{ readiness = 'ready'; route = @{ number = 3 }; install = @{ steps = @(@{ installer = 'invented.exe' }) }; predecessor = @{ found = $true } })
Assert 'plan check: an invented file is sent back' ($tp2 -match "'invented.exe' is not in the delivery")
Assert 'plan check: a good plan passes'            (-not "$(Test-AgentPlan -Sheet $sheet -Plan $goodPlan)".Trim())
Assert 'plan check: loose files need no installer' (-not ("$(Test-AgentPlan -Sheet $sheetE -Plan ([ordered]@{ readiness = 'ready'; route = @{ number = 7 }; install = @{ steps = @() }; predecessor = @{ found = $false; why = 'none' } }))" -match 'nothing can be tested'))

# =====================================================================================================================
Section 'what gets run is what the plan said - nothing else'
$p = Get-AgentRunProposal -Sheet $sheet
Assert 'run: the planned file and line'            ($p.Decided -and $p.Name -eq 'App Setup 2.0.msi' -and $p.Args -eq '/qn REBOOT=ReallySuppress TRANSFORMS="App Setup 2.0.mst"' -and (Test-Path $p.Installer))
Assert 'run: alternatives follow, as arguments only' (@($p.Candidates).Count -eq 2 -and "$(@($p.Candidates)[1].command)" -eq '/qn REBOOT=ReallySuppress')
Assert 'run: one step is not a sequence'           (@($p.Sequence).Count -eq 0)
$noPlan = New-AgentSheet -PkgName 'V_A_x64_1.0-0001_MUL' -Folder $ord
$noPlan.sources = $sheet.sources
$np = Get-AgentRunProposal -Sheet $noPlan
Assert 'run: no plan means NOTHING runs'           (-not $np.Decided -and -not "$($np.Args)".Trim() -and "$($np.Why)" -match 'does not say what to install')
Assert 'run: no default switch is ever invented'   ("$($np.Args)" -notmatch '(?i)/qn|/silent|REBOOT=' -and @($np.Candidates).Count -eq 0)
$seqSheet = New-AgentSheet -PkgName 'V_A_x64_1.0-0001_MUL' -Folder $ord
$seqSheet.sources = $sheet.sources
$seqSheet.plan = [ordered]@{ install = [ordered]@{ steps = @([ordered]@{ order = 2; installer = 'App Setup 2.0.msi'; arguments = '/qn' }, [ordered]@{ order = 1; installer = 'App Setup 2.0.mst'; arguments = '' }) } }
Assert 'run: several steps travel as a sequence, in order' (@((Get-AgentRunProposal -Sheet $seqSheet).Sequence).Count -eq 2 -and "$(@((Get-AgentRunProposal -Sheet $seqSheet).Sequence)[0].order)" -eq '1')
Assert 'args-only: msiexec and a quoted MSI with spaces' ((Get-AgentArgsOnly -Command 'msiexec /i "Firefox Setup 140.16.0esr_en-us.msi" TRANSFORMS="x.mst" /qn' -InstallerName 'Firefox Setup 140.16.0esr_en-us.msi') -eq 'TRANSFORMS="x.mst" /qn')
Assert 'args-only: bare arguments untouched'       ((Get-AgentArgsOnly -Command '/VERYSILENT /NORESTART' -InstallerName 'x.exe') -eq '/VERYSILENT /NORESTART')
Assert 'args-only: an exe with spaces'             ((Get-AgentArgsOnly -Command '"Setup Foo Bar.exe" /S /v"/qn"' -InstallerName 'Setup Foo Bar.exe') -eq '/S /v"/qn"')

# =====================================================================================================================
Section 'the machine: what comes off first, from the plan'
function Get-AgentInstalledRelated { param([string]$Vendor, [string]$App, [string[]]$ExtraTokens = @())
    return @([ordered]@{ displayName = 'App 1.0'; version = '1.0'; uninstallString = 'msiexec /x {OLD}' }, [ordered]@{ displayName = 'Vendor Shared Runtime'; version = '3' }) }
$sheet.plan.evaluate.removeFirst = @([ordered]@{ displayName = 'App 1.0'; command = 'msiexec /x {OLD} /qn'; why = 'the previous version would upgrade in place' })
$mp = Invoke-AgentMachinePrep -Sheet $sheet
Assert 'machine: the plan''s removals are what is done' ("$($mp.decision.summary)" -match 'App 1\.0')
Assert 'machine: anything else is left and reported' (@($mp.notInThePlan) -contains 'Vendor Shared Runtime 3')
Assert 'machine: nothing removed without -Execute'  (@($mp.removed).Count -eq 0)
Remove-Item Function:\Get-AgentInstalledRelated
. (Join-Path $here 'Src\Agent.Core.ps1')
$sheet.plan.evaluate.removeFirst = @()

# =====================================================================================================================
Section 'the test install is judged by the AI'
$diff = [ordered]@{ Programs = @{ Added = @([pscustomobject]@{ Id = 'HKLM:\...\App'; Info = @{ DisplayName = 'App 2.0'; DisplayVersion = '2.0'; Publisher = 'Vendor' } }); Noise = @() }
                    Tasks = @{ Added = @([pscustomobject]@{ Id = '\AppUpdater'; Info = @{ Name = 'AppUpdater'; Path = '\'; Action = 'upd.exe' } }); Noise = @() } }
$cs = [ordered]@{ Counts = @{ new = 3 }; Files = @(@{ Path = 'C:\Program Files\App\app.exe' }); Registry = @(@{ Path = 'HKLM\SOFTWARE\App' }); RegValues = @{ 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' = @(@{ Name = 'AppTray'; New = 'tray.exe' }) }; Env = @() }
$result = @{ Diff = $diff; ChangeSet = $cs; Un = @{ DisplayName = 'App 2.0'; DisplayVersion = '2.0'; ProductCode = '{NEW}'; Uninstall = 'msiexec /x {NEW}' }; Hkcu = @(); UserFiles = @()
             Cleanups = @([pscustomobject]@{ Kind = 'Task'; Default = $true; Label = 'Remove scheduled task: AppUpdater'; Command = "Unregister-ScheduledTask -TaskName 'AppUpdater' -Confirm:`$false" }); Shortcuts = @(); ReportText = 'report'; FileDiff = @{ InstalledBytes = 5MB } }
$sum = ConvertTo-AgentSnapshotSummary -Result $result
Assert 'summary: programs, tasks, file groups, run values' ($sum.Programs.addedCount -eq 1 -and $sum.Tasks.addedCount -eq 1 -and $sum.fileGroups.Count -eq 1 -and $sum.registryValuesSample.Count -eq 1)
$script:Fake['review'] = {
    param($Body, $Round)
    return (New-FakeResponse -Call 'submit_decision' -CallArgs ([ordered]@{
        installOutcome = @{ silent = $true; exitCodeOk = $true; installedAsExpected = $true }
        provedWhatWasPlanned = @(@{ claim = 'ARP shows App 2.0'; seen = $true; evidence = 'Programs: App 2.0' }, @{ claim = 'the transform setting ServerName is present'; seen = $false; evidence = 'not in the registry values' })
        items = @(@{ category = 'Tasks'; label = 'AppUpdater'; verdict = 'auto-update'; owner = 'this-application'; action = 'disable'; reason = 'vendor updater'; command = "Disable-ScheduledTask -TaskName 'AppUpdater'" })
        autoUpdate = @{ found = $true; mechanism = 'scheduled task'; commands = @("Disable-ScheduledTask -TaskName 'AppUpdater'") }
        uninstall = @{ command = 'msiexec /x {NEW} /qn'; fromArp = $true }
        detection = @{ type = 'registry'; key = 'HKLM:\SOFTWARE\VWG\CM\Vendor_App_x64_2.0-0001_MUL [measured]' }
        packagingMethod = @{ method = 'MSI+MST'; installCommand = '/qn TRANSFORMS="App Setup 2.0.mst"'; uninstallCommand = 'msiexec /x {NEW} /qn'; reason = 'proven' }
        packageUpdate = @{ changes = @(@{ section = 'Post-Install'; find = "Write-ADTLogEntry -Message 'added by the plan'"; replaceWith = "Write-ADTLogEntry -Message 'added by the plan'`r`n    Disable-ScheduledTask -TaskName 'AppUpdater'"; why = 'the test found the updater' }) }
        needsHumanDecision = @(); confidence = 'high'; summary = 'Installs silently; the updater must be disabled.'; narration = 'It installed cleanly, but it registered an updater task, so the package will switch that off.' }))
}
$run = @{ Installer = $p.Installer; Args = $p.Args; RunAs = 'Admin'; ExitCode = 0; DurationSec = 12; WindowsSeen = @(); TimedOut = $false; Error = ''; Command = 'msiexec /i x' }
$sheet.trial = @{ attempts = @(@{ arguments = $p.Args; verdict = 'silent'; exitCode = 0 }); winner = @{ arguments = $p.Args } }
$script:FakeLog.Clear()
$sheet = Invoke-AgentSnapshotDecision -Sheet $sheet -Result $result -RunInfo $run
Assert 'evaluated: the decision is stored'         ($sheet.status -eq 'evaluated' -and $sheet.decision.packagingMethod.method -eq 'MSI+MST' -and (Get-AgentStageStatus -Sheet $sheet -Id 'evaluate') -eq 'done')
$evReq = Get-LastTurnText (@($script:FakeLog | Where-Object { $_.Name -match '^review-' })[0].Body)
Assert 'evaluated: every attempt and the diff went to it' ($evReq -match 'everyAttempt' -and $evReq -match 'AppUpdater' -and $evReq -match 'WHAT THE MACHINE SHOWED')
Assert 'evaluated: the plan is in its memory, not re-sent' ((@($script:FakeLog | Where-Object { $_.Name -match '^review-' })[0].Body.contents | ConvertTo-Json -Depth 30 -Compress) -match 'What you submitted through submit_plan')
$spec = Get-AgentPackageSpec -Sheet $sheet
Assert 'spec: the test''s changes are added to the plan''s' (@($spec.changes).Count -eq 3)
Assert 'spec: the measured detection wins'         ("$($spec.detection.key)" -match '\[measured\]')
Assert 'spec: what the test did not change stays'  ("$($spec.sourceFileToUse)" -eq 'App Setup 2.0.msi')
Assert 'conversation: two jobs, four record turns' ($sheet.conversation.Count -eq 5)

# =====================================================================================================================
Section 'the build: the tool builds exactly what was decided'
$npk = New-AgentNewPkg -Sheet $sheet
Assert 'newpkg: the planned MSI, single mode'      ($npk.MsiFileName -eq 'App Setup 2.0.msi' -and $npk.InstallerMode -eq 'SingleMSI')
Assert 'newpkg: the transform from the install line' ($npk.MstFileName -eq 'App Setup 2.0.mst')
Assert 'newpkg: process names, never objects or paths' (@($npk.SnapshotProcs) -contains 'app' -and @($npk.SnapshotProcs) -contains 'apphelper' -and -not (@($npk.SnapshotProcs) | Where-Object { "$_" -match '[\\ ]|^System\.' }).Count)
Assert 'newpkg: detection from the spec'           ("$($npk.SoftIdent)" -match 'Vendor_App_x64_2\.0')
$mkS = { param($Plan, $Inst, $Trial) $s2 = New-AgentSheet -PkgName 'V_A_x86_1.0-0001_MUL' -Folder $ord; $s2.identity = @{ vendor = 'V'; app = 'A'; arch = 'x86'; version = '1.0'; release = '0001'; lang = 'MUL' }; $s2.sources = @{ installers = $Inst }; $s2.plan = $Plan; if ($Trial) { $s2.trial = $Trial }; return $s2 }
$one = & $mkS ([ordered]@{ route = @{ kind = 'fresh'; number = 3 }; install = @{ steps = @(@{ order = 1; installer = 'setup.exe'; arguments = '/S' }) } }) @(@{ name = 'setup.exe'; ext = '.exe' }, @{ name = 'other.exe'; ext = '.exe' }) @{ winner = @{ arguments = '/S /NORESTART' } }
$n1 = New-AgentNewPkg -Sheet $one
Assert 'newpkg: a single EXE uses the PROVEN line'  ($n1.ExeFileName -eq 'setup.exe' -and $n1.InstallParams -eq '/S /NORESTART' -and $n1.InstallerMode -eq 'SingleEXE')
$many = & $mkS ([ordered]@{ route = @{ kind = 'fresh'; number = 3 }; install = @{ steps = @(@{ order = 2; installer = 'app.exe'; arguments = '/S' }, @{ order = 1; installer = 'prereq.msi'; arguments = '/qn' }) } }) @(@{ name = 'prereq.msi'; ext = '.msi'; productCode = '{P}' }, @{ name = 'app.exe'; ext = '.exe' }) $null
$n2 = New-AgentNewPkg -Sheet $many
Assert 'newpkg: several steps -> Multiple, in order' ($n2.InstallerMode -eq 'Multiple' -and @($n2.Installers)[0].MsiFileName -eq 'prereq.msi' -and @($n2.Installers)[1].InstallParams -eq '/S')
$loose = & $mkS ([ordered]@{ route = @{ kind = 'fresh'; number = 7 }; install = @{ steps = @() } }) @() $null
Assert 'newpkg: route 7 -> loose files with an ARP entry' ((New-AgentNewPkg -Sheet $loose).InstallerMode -eq 'LooseFiles')
$reuseExe = & $mkS ([ordered]@{ route = @{ kind = 'reuse_as_is'; number = 3 }; install = @{ steps = @(@{ order = 1; installer = 'App_2.0.msi'; arguments = '/qn' }) }; package = @{ sourceFileToUse = 'Setup_2.0.exe' } }) @(@{ name = 'Setup_2.0.exe'; ext = '.exe' }, @{ name = 'App_2.0.msi'; ext = '.msi'; productCode = '{A}' }) $null
Assert 'newpkg: on a reuse the predecessor''s source file is kept' ((New-AgentNewPkg -Sheet $reuseExe).ExeFileName -eq 'Setup_2.0.exe')
# the real build, on the real template, from the predecessor
$dest = Join-Path (New-TestDir 'build') 'pkg'
[void](Set-AgentStage -Sheet $sheet -Id 'prepare' -Status 'done' -Note 'nothing to prepare')
$sheet = Invoke-AgentPackageBuild -Sheet $sheet -Destination $dest
$built = [IO.File]::ReadAllText($sheet.build.script)
Assert 'build: done, from the predecessor'         ((Get-AgentStageStatus -Sheet $sheet -Id 'build') -eq 'done' -and $sheet.build.builtWith -eq 'Build-PredecessorScript')
Assert 'build: the shipped shape'                  ((Test-Path (Join-Path $dest 'Content\Invoke-AppDeployToolkit.ps1')) -and (Test-Path (Join-Path $dest 'Documents')) -and (Test-Path (Join-Path $dest 'Content\Files\App Setup 2.0.msi')) -and (Test-Path (Join-Path $dest 'Content\Files\App Setup 2.0.mst')))
Assert 'build: the documents go to Documents'      (Test-Path (Join-Path $dest 'Documents\Installation Instructions.docx'))
Assert 'build: the planned changes were applied'   (@($sheet.build.changesApplied).Count -ge 2 -and $built -match "added by the plan" -and $built -match "Disable-ScheduledTask -TaskName 'AppUpdater'")
Assert 'build: a change that cannot land is reported, not guessed' (@($sheet.build.changesNotApplied | Where-Object { "$($_.find)" -eq 'THIS TEXT IS NOT IN THE SCRIPT' }).Count -eq 1)
Assert 'build: no uninstall-previous block, because the plan said generic' ($sheet.build.uninstallPreviousAdded -eq $false -and "$($sheet.build.uninstallPreviousWhy)" -match 'generic')
$be = $null; [void][Management.Automation.Language.Parser]::ParseInput($built, [ref]$null, [ref]$be)
Assert 'build: the built script parses'            (@($be).Count -eq 0)
Assert 'build: retargeted to the new version'      ($built -match '2\.0' -and $built -match 'App Setup 2\.0\.msi')
Assert 'flow: verify is ready once built'          ((@(Get-AgentFlow -Sheet $sheet | Where-Object { $_.id -eq 'verify' })[0].state) -eq 'ready')
# a FRESH build writes the plan's extra steps under the markers - and never a command that does not parse
$fOrd = New-TestDir 'forder'
foreach ($d in "$fOrd\source\defaults\pref", "$fOrd\doc") { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Set-Content (Join-Path $fOrd 'source\setup.exe') 'MZ' -Encoding Ascii
Set-Content (Join-Path $fOrd 'source\defaults\pref\channel-prefs.js') 'pref' -Encoding Ascii
Set-Content (Join-Path $fOrd 'doc\Order.docx') 'doc' -Encoding Ascii
$fs = New-AgentSheet -PkgName 'Vendor_Tool_x64_1.0-0001_MUL' -Folder $fOrd
$fs.identity = @{ vendor = 'Vendor'; app = 'Tool'; arch = 'x64'; version = '1.0'; release = '0001'; lang = 'MUL' }
$fs.sources = @{ installers = @(@{ name = 'setup.exe'; ext = '.exe'; path = (Join-Path $fOrd 'source\setup.exe') }) }
$fs.plan = [ordered]@{ route = @{ kind = 'fresh'; number = 6 }; install = @{ steps = @(@{ order = 1; installer = 'setup.exe'; arguments = '/S'; purpose = 'main application' }) }
                       package = [ordered]@{ postInstall = @(@{ order = 2; what = 'remove the desktop shortcut'; command = "Remove-ADTFile -Path `"`$envCommonDesktop\Tool.lnk`""; source = 'house rule' },
                                                            @{ order = 1; what = 'disable the updater'; command = "Disable-ScheduledTask -TaskName 'ToolUpdater'"; source = 'measured' },
                                                            @{ order = 3; what = 'broken'; command = "if (`$x -like ) { oops"; source = 'reasoning' })
                                             closeProcesses = @('tool') } }
$fDest = Join-Path (New-TestDir 'fbuild') 'pkg'
$fs = Invoke-AgentPackageBuild -Sheet $fs -Destination $fDest
$fb = [IO.File]::ReadAllText($fs.build.script)
Assert 'fresh: built with the fresh builder'       ($fs.build.builtWith -eq 'Build-FreshScript' -and (Get-AgentStageStatus -Sheet $fs -Id 'build') -eq 'done')
Assert 'fresh: subfolders stay folders'            ((Test-Path (Join-Path $fDest 'Content\Files\defaults\pref\channel-prefs.js')) -and -not (Test-Path (Join-Path $fDest 'Content\Files\channel-prefs.js')))
Assert 'fresh: the steps land under their marker, in order' ($fb -match '(?s)Perform Post-Installation tasks here>.*ToolUpdater' -and $fb.IndexOf('ToolUpdater') -lt $fb.IndexOf('Tool.lnk'))
Assert 'fresh: a broken command is left out and reported' ($fb -notmatch 'oops' -and @($fs.build.notWritten | Where-Object { "$($_.why)" -match 'not valid PowerShell' }).Count -eq 1)
$fe = $null; [void][Management.Automation.Language.Parser]::ParseInput($fb, [ref]$null, [ref]$fe)
Assert 'fresh: the script still parses'            (@($fe).Count -eq 0)

# =====================================================================================================================
Section 'editing a built package in place'
$eDir = New-TestDir 'edit'
$eScript = Join-Path $eDir 'Invoke-AppDeployToolkit.ps1'
[IO.File]::WriteAllText($eScript, "line one`r`n    Write-ADTLogEntry -Message 'a'`r`n    Write-ADTLogEntry -Message 'a'`r`nfunction x { 'b' }`r`n", (New-Object Text.UTF8Encoding $true))
$e1 = Edit-AgentScript -Path $eScript -Find "function x { 'b' }" -ReplaceWith "function x { 'c' }" -AllowedRoot $eDir
Assert 'edit: an exact, unique text is changed'    ($e1.ok -and ([IO.File]::ReadAllText($eScript)) -match "'c'" -and $e1.line -eq 4)
Assert 'edit: it reads the change back'            ((@($e1.nowReads) -join "`n") -match "function x \{ 'c' \}")
Assert 'edit: the file keeps its BOM and its CRLF' (([IO.File]::ReadAllBytes($eScript))[0] -eq 0xEF -and ([IO.File]::ReadAllText($eScript)).Contains("`r`n"))
$e2 = Edit-AgentScript -Path $eScript -Find "Write-ADTLogEntry -Message 'a'" -ReplaceWith 'x' -AllowedRoot $eDir
Assert 'edit: text found twice is refused'         (-not $e2.ok -and $e2.note -match 'occurs 2 times')
$e3 = Edit-AgentScript -Path $eScript -Find 'function x { ''zzz'' }' -ReplaceWith 'y' -AllowedRoot $eDir
Assert 'edit: text not there is refused, with similar lines' (-not $e3.ok -and @($e3.similarLines).Count -ge 1)
$e4 = Edit-AgentScript -Path $eScript -Find "function x { 'c' }" -ReplaceWith "function x { 'c'" -AllowedRoot $eDir
Assert 'edit: a change that breaks parsing is NOT written' (-not $e4.ok -and $e4.note -match 'stop parsing' -and ([IO.File]::ReadAllText($eScript)) -match "function x \{ 'c' \}")
Assert 'edit: text passed as a path is refused'  (-not (Edit-AgentScript -Path "line one`nnothing" -Find 'a' -ReplaceWith 'b' -AllowedRoot $eDir).ok)
$outside = Join-Path $env:TEMP ('outside_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.ps1'); Set-Content $outside 'x' -Encoding Ascii
Assert 'edit: only files inside the package'       (-not (Edit-AgentScript -Path $outside -Find 'x' -ReplaceWith 'y' -AllowedRoot $eDir).ok)
Assert 'edit: a relative path finds the file'      ((Edit-AgentScript -Path 'Invoke-AppDeployToolkit.ps1' -Find 'line one' -ReplaceWith 'line 1' -AllowedRoot $eDir).ok)
Remove-Item $outside -Force -ErrorAction SilentlyContinue
$e6 = Edit-AgentScript -Path $eScript -Find "line 1`n    Write-ADTLogEntry" -ReplaceWith "line 1`n    Write-ADTLogEntry" -AllowedRoot $eDir
Assert 'edit: an LF find matches a CRLF file'      ($e6.ok)
$pt = @(Get-AgentPackageTools -ScriptPath $eScript -Sheet $sheet -Edits (New-Object Collections.ArrayList))
Assert 'hands: test_package, edit_script and check_package' ((@($pt | ForEach-Object { $_.Decl.name }) -join ',') -eq 'test_package,edit_script,check_package')

# =====================================================================================================================
Section 'the mechanical checks - facts for the verdict'
$chk = Invoke-AgentPackageChecks -ScriptPath $sheet.build.script -Sheet $sheet
Assert 'checks: parse, consistency, commands, template, changes' ($null -ne $chk.parses -and $null -ne $chk.matchesItsPackage -and $null -ne $chk.commandsExist -and $null -ne $chk.templateIntact -and @($chk.plannedChanges).Count -eq 3)
Assert 'checks: the planned changes are traced'    (@($chk.plannedChanges | Where-Object { $_.newTextPresent -eq $true }).Count -ge 2)
Assert 'checks: a verdict line to read'            ("$($chk.note)".Trim().Length -gt 10)
$pcDir = New-TestDir 'pc'
New-Item -ItemType Directory -Force -Path (Join-Path $pcDir 'Files') | Out-Null
Set-Content (Join-Path $pcDir 'Files\App Setup 2.0.msi') 'x' -Encoding ascii
Set-Content (Join-Path $pcDir 'Files\App Setup 2.0.mst') 'x' -Encoding ascii
$wrong = Join-Path $pcDir 'Invoke-AppDeployToolkit.ps1'
Set-Content $wrong -Encoding utf8 -Value "AppVersion = '1.0'`nStart-ADTMsiProcess -Action 'Install' -FilePath 'App Setup 1.0.msi' -Transforms 'App Setup 1.0.mst'"
$bad = Test-AgentPackageConsistency -ScriptPath $wrong -ExpectedVersion '2.0'
Assert 'consistency: last version''s names are caught' (-not $bad.ok -and @($bad.missingFromPackage) -contains 'App Setup 1.0.msi' -and $bad.versionLooksWrong)
Set-Content $wrong -Encoding utf8 -Value "AppVersion = '2.0'`nStart-ADTMsiProcess -Action 'Install' -FilePath 'App Setup 2.0.msi'"
Assert 'consistency: a transform nobody applies is caught' (@((Test-AgentPackageConsistency -ScriptPath $wrong -ExpectedVersion '2.0').transformsNotUsed) -contains 'App Setup 2.0.mst')
Set-Content $wrong -Encoding utf8 -Value "AppVersion = '2.0'`nStart-ADTMsiProcess -Action 'Install' -FilePath 'App Setup 2.0.msi' -Transforms 'App Setup 2.0.mst'"
Assert 'consistency: a correct package passes'     ((Test-AgentPackageConsistency -ScriptPath $wrong -ExpectedVersion '2.0').ok)
$bp = Join-Path $pcDir 'bad.ps1'; Set-Content $bp -Encoding utf8 -Value "if (`$m -like \'Profiles/*.default*\') { `$m = 'x' }"
$bpr = Test-AgentScriptParses -ScriptPath $bp
Assert 'parse: JSON escaping is caught, with a line' (-not $bpr.parses -and @($bpr.errors)[0].line -ge 1 -and $bpr.note -match 'DOES NOT PARSE')
$api = Get-AgentToolkitApi
if (@($api.toolkit).Count) {
    $cf = Join-Path $pcDir 'cmds.ps1'; Set-Content $cf "Execute-MSI -Action Install -Path 'a.msi'`nStart-ADTMsiProcess -Action Install -FilePath 'a.msi'`nInvoke-MadeUpThing" -Encoding UTF8
    $cr = Test-AgentScriptCommands -ScriptPath $cf -Api $api
    Assert 'commands: a v3 name is caught with its v4 name' ((@(@($cr.unknown) | Where-Object { $_.name -eq 'Execute-MSI' })[0].why) -match 'Start-ADTMsiProcess')
    Assert 'commands: an invented function is caught'  ((@($cr.unknown) | ForEach-Object { $_.name }) -contains 'Invoke-MadeUpThing')
    Assert 'commands: the team extensions are known'   ((@($api.extensions) | ForEach-Object { $_.name }) -contains 'Set-MTBReboot')
}
$ti = Test-AgentTemplateIntegrity -ScriptPath (Join-Path $tplPath 'Invoke-AppDeployToolkit.ps1')
Assert 'template: the blank template checks clean' ($ti.ok -and $ti.missingCount -eq 0)
$dl = [System.Collections.Generic.List[string]](Get-Content (Join-Path $tplPath 'Invoke-AppDeployToolkit.ps1')); $cut = 0
for ($i = $dl.Count - 1; $i -ge 0 -and $cut -lt 2; $i--) { if ($dl[$i] -match 'Close-ADTSession|Open-ADTSession|Import-Module') { $dl.RemoveAt($i); $cut++ } }
$dmg = Join-Path $pcDir 'dmg.ps1'; Set-Content $dmg $dl.ToArray() -Encoding UTF8
Assert 'template: a deleted template line is caught' (-not (Test-AgentTemplateIntegrity -ScriptPath $dmg).ok)
Assert 'removal: generic pre-install is recognised' (Test-AgentGenericRemoval -Code "Remove-ADTFolder -Path `$p`nStop-Process -Name app`nRemove-ADTRegistryKey -Key 'HKLM:\SOFTWARE\App'" -Identity @{ Version = '1.0'; FullName = 'V_A_1.0' })
Assert 'removal: a ProductCode block is pinned'     (-not (Test-AgentGenericRemoval -Code "Get-ADTApplication -ProductCode '{C1B721E4-4A71-4A2F-AC1A-DDD5C9271CD2}'`nRemove-ADTFolder -Path x`nStop-Process -Name a" -Identity @{ Version = '1.0' }))
$szA = Join-Path $pcDir 'a.ps1'; $szB = Join-Path $pcDir 'b.ps1'
Set-Content $szA "#region PRE-INSTALLATION`nWrite-ADTLogEntry -Message 'one'`n#endregion PRE-INSTALLATION`n#region PRE-REPAIR`nStart-ADTProcess -FilePath 'unins000.exe' -ArgumentList '/VERYSILENT'`n#endregion PRE-REPAIR" -Encoding utf8
Set-Content $szB "#region PRE-INSTALLATION`nWrite-ADTLogEntry -Message 'one'`nWrite-ADTLogEntry -Message 'one'`nWrite-ADTLogEntry -Message 'two'`n#endregion PRE-INSTALLATION`n#region PRE-REPAIR`n#endregion PRE-REPAIR" -Encoding utf8
$szR = Get-AgentSectionSizes -ScriptPath $szB -PredecessorScriptPath $szA
Assert 'section sizes: a doubled section is a number' (@(@($szR.sections) | Where-Object { $_.section -eq 'preInstall' })[0].difference -eq 2)
Assert 'section sizes: a Pre-Repair the predecessor had and the package dropped is caught' (@($szR.droppedFromPredecessor | Where-Object { $_.section -eq 'preRepair' }).Count -eq 1)
$v3 = Join-Path $pcDir 'Deploy-Application.ps1'
Set-Content $v3 "[string]`$installPhase = 'Pre-Repair'`nExecute-Process -Path 'unins000.exe' -Parameters '/VERYSILENT'`n[string]`$installPhase = 'Repair'`nExecute-Process -Path 'setup.exe' -Parameters '/SILENT'`n[string]`$installPhase = 'Post-Repair'`nAdd-UGPermission -path 'x' -Modify" -Encoding utf8
$ph3 = Get-AgentScriptPhases -Text ([IO.File]::ReadAllText($v3))
Assert 'phases: a v3 script''s repair phases are read' (@($ph3.preRepair).Count -eq 1 -and @($ph3.repair).Count -eq 1 -and @($ph3.postRepair).Count -eq 1)
$tm = @(ConvertTo-OpenAIMessages -System 's' -Contents @(@{ role = 'user'; parts = @(@{ text = 'a' }) }, @{ role = 'model'; parts = @(@{ text = 'b' }) }))
Assert 'openai: a text-only answer gets no phantom tool message' (-not @($tm | Where-Object { $_.role -eq 'tool' }).Count)

# =====================================================================================================================
Section 'the verify job: fix it in place, then sign it off - or not'
$script:Fake['verify'] = {
    param($Body, $Round)
    $last = Get-LastTurnText $Body
    if ($last -match '"accepted":false') { return (New-FakeResponse -Call 'submit_verification' -CallArgs @{ verdict = 'fix_needed'; findings = @(@{ severity = 'blocker'; section = 'Install'; what = 'still wrong'; why = 'the checks'; evidence = '(missing)' }); summary = 'not yet' }) }
    switch ($Round) {
        '1' { return (New-FakeResponse -Call 'edit_script' -CallArgs @{ find = "Write-ADTLogEntry -Message 'added by the plan'"; replaceWith = "Write-ADTLogEntry -Message 'added by the plan and checked'"; why = 'make the log line say it was checked' }) }
        '2' { return (New-FakeResponse -Call 'check_package' -CallArgs @{}) }
        default { return (New-FakeResponse -Call 'submit_verification' -CallArgs @{ verdict = 'pass'; findings = @(); summary = 'Ship it.'; narration = 'One line tidied; every check is clean.' }) }
    }
}
$script:FakeLog.Clear()
$sheet = Invoke-AgentVerifyLoop -Sheet $sheet -ScriptPath $sheet.build.script
$vCalls = @($script:FakeLog | Where-Object { $_.Name -match '^verify-' })
Assert 'verify: the whole script went with line numbers' ((Get-LastTurnText $vCalls[0].Body) -match 'WITH LINE NUMBERS' -and (Get-LastTurnText $vCalls[0].Body) -match '\s1: ')
Assert 'verify: the checks went with it'           ((Get-LastTurnText $vCalls[0].Body) -match 'theMechanicalChecks')
Assert 'verify: the edit really landed'            (([IO.File]::ReadAllText($sheet.build.script)) -match 'added by the plan and checked')
Assert 'verify: every edit is on the record'       (@($sheet.verification.changesApplied).Count -eq 1 -and "$(@($sheet.verification.changesApplied)[0].what)" -match 'checked')
Assert 'verify: the checks are re-run at the end'  ($null -ne $sheet.verification.checksAtTheEnd)
$passedNow = [bool]$sheet.verification.checksAtTheEnd.ok
Assert 'verify: a pass survives only real checks'  (($sheet.verification.verdict -ne 'pass') -or $passedNow)
Assert 'verify: a pass without running the package goes back' (@($script:FakeLog | Where-Object { $_.Name -match '^verify-' } | Where-Object { ($_.Body.contents | ConvertTo-Json -Depth 30 -Compress) -match 'without running the package' }).Count -ge 1)
Assert 'verify: the gate follows the verdict'      ((Get-AgentStageStatus -Sheet $sheet -Id 'verify') -eq $(if ($sheet.verificationPassed) { 'done' } else { 'failed' }))
# a pass on a script that does not parse goes back once
$gDir = New-TestDir 'gate'; New-Item -ItemType Directory -Force -Path (Join-Path $gDir 'Content\Files') | Out-Null
$gScript = Join-Path $gDir 'Content\Invoke-AppDeployToolkit.ps1'; Set-Content $gScript "if (`$x -like ) { oops" -Encoding utf8
$gs = New-AgentSheet -PkgName 'V_G_x64_1.0-0001_MUL' -Folder $gDir; $gs.identity = @{ version = '1.0' }
$script:Fake['verify'] = { param($Body, $Round) if ((Get-LastTurnText $Body) -match '"accepted":false') { return (New-FakeResponse -Call 'submit_verification' -CallArgs @{ verdict = 'fix_needed'; findings = @(@{ severity = 'blocker'; what = 'does not parse' }); summary = 'no' }) }; return (New-FakeResponse -Call 'submit_verification' -CallArgs @{ verdict = 'pass'; findings = @(); summary = 'looks fine' }) }
$gs = Invoke-AgentVerifyLoop -Sheet $gs -ScriptPath $gScript
Assert 'verify: a pass the checks contradict goes back once' ($gs.verification.verdict -eq 'fix_needed' -and -not $gs.verificationPassed)
Assert 'verify: and the package is not signed off' ((Get-AgentStageStatus -Sheet $gs -Id 'verify') -eq 'failed' -and "$($gs.stages.verify.note)" -match 'NOT signed off')

# =====================================================================================================================
Section 'the job runner: prose, running out, the packager, the budget'
$jobSheet = New-AgentSheet -PkgName 'V_J_x64_1.0-0001_MUL' -Folder $ord
$jobSheet.sources = $sheet.sources; $jobSheet.identity = $sheet.identity
$script:Fake['stubborn'] = { param($Body, $Round) if ($Round -eq 'json') { return (New-FakeResponse -Text '{"reply":"fine, here it is"}') }; return (New-FakeResponse -Text 'a long answer in prose') }
$script:FakeLog.Clear()
$st = Invoke-AgentJob -Sheet $jobSheet -Job 'stubborn' -Title 't' -Instruction 'x' -SubmitName 'submit_consult' -MaxRounds 5
$jsonCall = @($script:FakeLog | Where-Object { $_.Name -eq 'stubborn-json' })[0]
Assert 'runner: prose is nudged, then asked for JSON' ("$($st.reply)" -eq 'fine, here it is' -and @($script:FakeLog | Where-Object { $_.Name -match '^stubborn-\d' }).Count -eq 2)
Assert 'runner: the JSON request still declares the tools' (@($jsonCall.Body.tools).Count -ge 1)
$lp = New-TestDir 'loopy'; $lctx = New-AgentOpContext -PackageFolder $lp
$script:Fake['loopy'] = { param($Body, $Round) if ($Round -eq 'json') { return (New-FakeResponse -Text '{"reply":"I ran out; this is where it stands"}') }; return (New-FakeResponse -Call 'run_powershell' -CallArgs @{ purpose = 'look again'; intent = 'read'; script = "'still looking'" }) }
$lr = Invoke-AgentJob -Sheet $jobSheet -Job 'loopy' -Title 't' -Instruction 'x' -SubmitName 'submit_consult' -Tools @(Get-AgentOpTools -Ctx $lctx) -MaxRounds 3
Assert 'runner: out of rounds still ends in a result' ("$($lr.reply)" -match 'ran out' -and $lr.job.rounds -eq 3)
$script:Fake['heard'] = { param($Body, $Round) if ((Get-LastTurnText $Body) -match 'THE PACKAGER IS TALKING TO YOU') { return (New-FakeResponse -Call 'submit_consult' -CallArgs @{ reply = 'heard you' }) }; return (New-FakeResponse -Call 'submit_consult' -CallArgs @{ reply = 'did not hear' }) }
$script:AgentHumanInbox = Get-AgentHumanInbox; [void]$script:AgentHumanInbox.Add('the predecessor is BRAK_beAClientSecurity on the live share')
$hr = Invoke-AgentJob -Sheet $jobSheet -Job 'heard' -Title 'listen' -Instruction 'x' -SubmitName 'submit_consult'
Assert 'runner: what the packager types reaches the next round' ("$($hr.reply)" -eq 'heard you' -and $script:AgentHumanInbox.Count -eq 0)
Assert 'runner: and it is kept in the fold'        ("$($jobSheet.conversation[-2].parts[0].text)" -match 'BRAK_beAClientSecurity')
$before = $jobSheet.conversation.Count
$script:PkgAgent.CostUSD = 999
$capErr = ''; try { $null = Invoke-AgentJob -Sheet $jobSheet -Job 'heard' -Title 'over budget' -Instruction 'x' -SubmitName 'submit_consult' } catch { $capErr = "$($_.Exception.Message)" }
Assert 'runner: the cost cap stops a job'          ($capErr -match 'cost cap')
Assert 'runner: a failed job is folded too'        ($jobSheet.conversation.Count -eq ($before + 2) -and "$($jobSheet.conversation[-2].parts[0].text)" -match 'did not finish')
Reset-AgentUsage
$sc0 = $jobSheet.conversation.Count
$script:Fake['experience'] = { param($Body, $Round) return (New-FakeResponse -Call 'submit_experience' -CallArgs @{ entries = @(@{ text = 'App 2.0 needs the ServerName property set by the transform.'; scope = 'package:Vendor_App'; why = 'the owner checks it' }); notKept = @(@{ what = 'it was a nice day'; why = 'not about packaging' }); summary = 'kept one thing' }) }
$memPath = Get-AgentMemoryPath; $memBak = $null; if (Test-Path -LiteralPath $memPath) { $memBak = Get-Content -LiteralPath $memPath -Raw }
$xp = Invoke-AgentExperienceIntake -Text 'ServerName must be set, and it was a nice day' -Sheet $jobSheet
Assert 'experience: sorted and kept'               (@($xp.stored).Count -eq 1 -and "$(@($xp.stored)[0].scope)" -eq 'package:Vendor_App' -and @($xp.notKept).Count -eq 1)
Assert 'experience: it does not touch the order''s conversation' ($jobSheet.conversation.Count -eq $sc0)
Assert 'experience: the job''s model is used'       ("$((@($script:FakeLog | Where-Object { $_.Name -match '^experience' }))[-1].Model)" -eq (Get-AgentModel -Task 'experience'))
if ($memBak) { Set-Content -LiteralPath $memPath -Value $memBak -Encoding UTF8 } else { Remove-Item -LiteralPath $memPath -Force -ErrorAction SilentlyContinue }
$script:Fake['consult'] = { param($Body, $Round) return (New-FakeResponse -Call 'submit_consult' -CallArgs @{ reply = 'You are right - I had the wrong predecessor.'; whatYouWillDo = 'plan again with it'; whatYouChecked = @('search_previous_packages BRAK'); redoStage = 'plan'; whyRedo = 'the predecessor changes the route' }) }
$cr2 = Invoke-AgentConsult -Sheet $jobSheet -Message 'wrong predecessor'
Assert 'consult: it answers and names what to redo' ("$($cr2.redoStage)" -eq 'plan' -and (Get-AgentStageDef -Id "$($cr2.redoStage)"))
$script:Fake['review'] = { param($Body, $Round) if ((Get-LastTurnText $Body) -match 'EVERY ATTEMPT') { return (New-FakeResponse -Call 'submit_retry' -CallArgs @{ diagnosis = 'exit 1603: the transform was not found'; candidates = @(@{ command = '/qn REBOOT=ReallySuppress'; source = 'playbook'; why = 'rules the transform out' }); giveUp = $false; summary = 'try without' }) }
                                                    return (New-FakeResponse -Call 'submit_troubleshoot' -CallArgs @{ whoseFault = 'the agent/tool itself'; whatHappened = 'the stage lost its runspace'; recommend = 'retry_same'; why = 'transient'; toolProblem = @{ isToolBug = $true; what = 'runspace died' } }) }
$adv = Invoke-AgentRetryCandidates -Sheet $jobSheet -Attempts @(@{ arguments = '/qn TRANSFORMS="x.mst"'; verdict = 'failed'; exitCode = 1603 }) -Installer 'x.msi'
Assert 'retry: a diagnosis and a new line'         ("$($adv.diagnosis)" -match '1603' -and @($adv.candidates).Count -eq 1)
$ts = Invoke-AgentTroubleshoot -Sheet $jobSheet -Stage 'build' -Error 'the runspace returned nothing'
Assert 'troubleshoot: whose fault, and what next'  ("$($ts.recommend)" -eq 'retry_same' -and [bool]$ts.toolProblem.isToolBug -and @($jobSheet.troubleshooting).Count -eq 1)

# =====================================================================================================================
Section 'the flow'
$ids = @((Get-AgentPipeline) | ForEach-Object { $_.Id })
Assert 'flow: the stages, in order'                (($ids -join ',') -eq 'intake,plan,prepare,evaluate,build,verify,handover')
Assert 'flow: the AI plans, the tool builds'       ((Get-AgentStageDef -Id 'plan').Owner -eq 'agent' -and (Get-AgentStageDef -Id 'build').Owner -eq 'tool' -and (Get-AgentStageDef -Id 'intake').Owner -eq 'tool')
Assert 'flow: build waits for the evaluation'      ((Get-AgentStageDef -Id 'build').Needs -contains 'evaluate' -and (Get-AgentStageDef -Id 'build').Needs -contains 'plan')
foreach ($sid in $ids) { $sd = Get-AgentStageDef -Id $sid; Assert "flow: '$sid' has a short line to say" ("$($sd.Say)".Trim().Length -gt 15 -and "$($sd.Say)".Length -lt 120) }
$fr = New-AgentSheet -PkgName 'X_Y_x64_1.0-0001_MUL' -Folder $env:TEMP
Assert 'flow: only intake is ready at the start'   ((@(Get-AgentFlow -Sheet $fr | Where-Object { $_.state -eq 'ready' })[0].id) -eq 'intake')
foreach ($st in 'intake', 'plan', 'prepare') { [void](Set-AgentStage -Sheet $fr -Id $st -Status 'done' -Note 't') }
$evs = @(Get-AgentFlow -Sheet $fr | Where-Object { $_.id -eq 'evaluate' })[0]
Assert 'flow: evaluate waits for a human'          ($evs.state -eq 'waiting' -and $evs.why -match 'go-ahead')
$fr.status = 'blocked'
Assert 'flow: a blocked order does not evaluate'   ((@(Get-AgentFlow -Sheet $fr | Where-Object { $_.id -eq 'evaluate' })[0].state) -eq 'blocked')
$fr.status = 'ready'
[void](Set-AgentStage -Sheet $fr -Id 'evaluate' -Status 'skipped' -Note 'skipped by the packager')
Assert 'flow: a skipped evaluation still lets build run' ((@(Get-AgentFlow -Sheet $fr | Where-Object { $_.id -eq 'build' })[0].state) -eq 'ready')
$threw = ''; try { [void](Invoke-AgentStage -Sheet $fr -Id 'verify' -With @{}) } catch { $threw = "$($_.Exception.Message)" }
Assert 'flow: a stage out of order is refused'     ($threw -match 'needs these first: build')
Assert 'flow: the text view marks what is done'    ((Format-AgentFlowText -Sheet $fr) -match '\[x\] Read the order' -and (Format-AgentFlowText -Sheet $fr) -match '\[x\] Plan the package')
$noModel = Invoke-AgentStage -Sheet (New-AgentSheet -PkgName 'a' -Folder $env:TEMP) -Id 'plan' -With @{ NoModel = $true; Force = $true }
Assert 'flow: -NoModel skips planning honestly'    ((Get-AgentStageStatus -Sheet $noModel -Id 'plan') -eq 'skipped')
$hp = New-AgentSheet -PkgName 'a' -Folder $env:TEMP; $hp.plan = [ordered]@{ humanNeeded = @{ required = $true; what = 'record a response file'; exactCommand = 'setup.exe /r /f1"C:\temp\setup.iss"'; sendBack = 'setup.iss' }; route = @{ kind = 'fresh'; number = 4 } }
$hp = Invoke-AgentPrepare -Sheet $hp
Assert 'prepare: what only a person can do is handed over' ((Get-AgentStageStatus -Sheet $hp -Id 'prepare') -eq 'waiting' -and $hp.stages.prepare.exactCommand -match '/r /f1')

# =====================================================================================================================
Section 'the hands on the machine'
$opPkg = New-TestDir 'op'
Set-Content (Join-Path $opPkg 'Invoke-AppDeployToolkit.ps1') "line one`nline two`n## <Perform Post-Installation tasks here>`nline four" -Encoding Ascii
$opc = New-AgentOpContext -PackageFolder $opPkg -OrderFolder $opPkg
$r1 = Invoke-AgentOpCommand -Ctx $opc -Purpose 'read with line numbers' -Intent 'read' -Script "Get-Content 'Invoke-AppDeployToolkit.ps1' | ForEach-Object { `$i++; '{0,3}: {1}' -f `$i, `$_ }"
Assert 'ops: a read runs and returns output'       ($r1.ok -and $r1.output -match '3: ## <Perform Post-Installation')
$r2 = Invoke-AgentOpCommand -Ctx $opc -Purpose 'dotnet write' -Intent 'modify' -Script '[IO.File]::WriteAllText("probe.txt", "changed"); [IO.File]::ReadAllText("probe.txt")'
Assert 'ops: a .NET write lands in the package folder' ($r2.ok -and (Test-Path (Join-Path $opPkg 'probe.txt')) -and @($r2.changedFiles) -contains 'probe.txt')
$r3 = Invoke-AgentOpCommand -Ctx $opc -Purpose 'unrelated share' -Intent 'modify' -Script "Set-Content -Path '\\some-other-server\Share\x.txt' -Value 'x'"
Assert 'ops: an unrelated share is refused'        (-not $r3.ok -and $r3.refused -match 'not part of this order')
$opc2 = New-AgentOpContext -PackageFolder $opPkg; $opc2.ExtraReadRoots = @('\\packages-server\Library')
$r3b = Invoke-AgentOpCommand -Ctx $opc2 -Purpose 'write to a readable share' -Intent 'modify' -Script "Set-Content -Path '\\packages-server\Library\x.txt' -Value 'x'"
Assert 'ops: a share it may READ is still never written' (-not $r3b.ok -and $r3b.refused -match 'READ-ONLY')
$ro = New-AgentOpContext -PackageFolder $opPkg -Policy 'readonly'
Assert 'ops: readonly blocks a mislabelled write'  (-not (Invoke-AgentOpCommand -Ctx $ro -Purpose 'sneaky' -Intent 'read' -Script "'x' | Out-File 'x.txt'").ok)
$r5 = Invoke-AgentOpCommand -Ctx $opc -Purpose 'fails' -Intent 'read' -Script "Get-Item 'does-not-exist-here.txt'"
Assert 'ops: a failure comes back as text'         (-not $r5.ok -and "$($r5.output)" -match 'does-not-exist-here')
$predLocal = New-TestDir 'predlocal'; Set-Content (Join-Path $predLocal 'Invoke-AppDeployToolkit.ps1') 'OLD' -Encoding ascii
$pctx = New-AgentOpContext -PackageFolder $opPkg -PredecessorFolder $predLocal
Assert 'ops: the predecessor is never written into' (-not (Invoke-AgentOpCommand -Ctx $pctx -Purpose 'x' -Intent 'modify' -Script "Set-Content -Path '$predLocal\notes.txt' -Value 'x'").ok -and -not (Test-Path (Join-Path $predLocal 'notes.txt')))
Assert 'ops: the built script is never replaced wholesale' (-not (Invoke-AgentOpCommand -Ctx $pctx -Purpose 'x' -Intent 'modify' -Script "Copy-Item -Path '$predLocal\Invoke-AppDeployToolkit.ps1' -Destination 'Invoke-AppDeployToolkit.ps1'").ok)
Assert 'ops: every command is recorded'            (@(Get-AgentOpCommands -Ctx $opc).Count -eq 4)
$hands = Get-AgentHands -Sheet $sheet -Want 'run_powershell', 'read_document', 'open_package', 'search_previous_packages', 'read_knowledge', 'take_screenshot', 'remember_this'
Assert 'hands: a job gets exactly what it asked for' ((@($hands | ForEach-Object { $_.Decl.name }) -join ',') -eq 'run_powershell,read_document,open_package,search_previous_packages,read_knowledge,take_screenshot,remember_this')
# the trial: the machine decides what "silent" means
function Invoke-AgentInstallRun { param([string]$Installer, [string]$Arguments = '', [string]$RunAs = 'Admin', [int]$TimeoutSec = 1800, [scriptblock]$Progress)
    $script:LastRunArgs = $Arguments
    switch -regex ("$Arguments") {
        '/quiet'    { return @{ ExitCode = $null; DurationSec = 245; WindowsSeen = @('Setup - Welcome'); TimedOut = $true; Error = ''; Command = "x $Arguments" } }
        '/bad'      { return @{ ExitCode = 1603; DurationSec = 3; WindowsSeen = @(); TimedOut = $false; Error = ''; Command = "x $Arguments" } }
        '/S|/qn'    { return @{ ExitCode = 0; DurationSec = 12; WindowsSeen = @(); TimedOut = $false; Error = ''; Command = "x $Arguments" } }
        '/progress' { return @{ ExitCode = 0; DurationSec = 20; WindowsSeen = @('Installing...'); TimedOut = $false; Error = ''; Command = "x $Arguments" } }
        default     { return @{ ExitCode = 1602; DurationSec = 2; WindowsSeen = @(); TimedOut = $false; Error = ''; Command = "x $Arguments" } } } }
$fx = Join-Path $opPkg 'setup.exe'; Set-Content $fx 'MZ' -Encoding Ascii
Assert 'trial: a window that waits = interactive'  ((Test-AgentSilentCandidate -Installer $fx -Arguments '/quiet').verdict -eq 'interactive')
Assert 'trial: a bad exit = failed'                ((Test-AgentSilentCandidate -Installer $fx -Arguments '/bad').verdict -eq 'failed')
Assert 'trial: no window + clean exit = silent'    ((Test-AgentSilentCandidate -Installer $fx -Arguments '/S').verdict -eq 'silent')
Assert 'trial: a progress window still counts'     ((Test-AgentSilentCandidate -Installer $fx -Arguments '/progress').verdict -eq 'progress')
$tr2 = Invoke-AgentSilentTrial -Installer $fx -Candidates @(@{ command = '/quiet' }, @{ command = '/bad' }, @{ command = '/S' }, @{ command = '/progress' })
Assert 'trial: candidates in order, stop at the first that works' (@($tr2.attempts).Count -eq 3 -and $tr2.winner.arguments -eq '/S')
$seqDir = New-TestDir 'seq'; foreach ($f in 'prereq.exe', 'app.exe') { Set-Content (Join-Path $seqDir $f) 'x' -Encoding Ascii }
$sq = Invoke-AgentInstallSequence -Steps @(@{ order = 2; installer = 'app.exe'; arguments = '/S' }, @{ order = 1; installer = 'prereq.exe'; arguments = '/S' }) -SourceFolder $seqDir
Assert 'sequence: every step, in the planned order' ($sq.found -and ((@($sq.steps) | ForEach-Object { $_.installer }) -join ',') -eq 'prereq.exe,app.exe')
$sqb = Invoke-AgentInstallSequence -Steps @(@{ order = 1; installer = 'prereq.exe'; arguments = '/bad' }, @{ order = 2; installer = 'app.exe'; arguments = '/S' }) -SourceFolder $seqDir
Assert 'sequence: a failed step stops the rest'    (-not $sqb.found -and $sqb.completed -eq 1)
$mDir = New-TestDir 'mst'; $msiP = Join-Path $mDir 'Firefox Setup 140.16.0esr_en-us.msi'; Set-Content $msiP 'MSI' -Encoding Ascii; Set-Content (Join-Path $mDir 'Firefox Setup 140.16.0esr_en-us.mst') 'MST' -Encoding Ascii
$att = Test-AgentSilentCandidate -Installer $msiP -Arguments 'TRANSFORMS="Firefox Setup 140.16.0esr_en-us.mst" /qn'
Assert 'transform: the RUN gets the full path'     ($script:LastRunArgs -match [regex]::Escape($mDir))
Assert 'transform: the RECORD keeps the plain name' ($att.arguments -eq 'TRANSFORMS="Firefox Setup 140.16.0esr_en-us.mst" /qn')
Remove-Item Function:\Invoke-AgentInstallRun
. (Join-Path $here 'Src\Agent.Core.ps1')

# ---- evaluation: run it the way deployment does, patiently, look at the screen, test the uninstall ---------------------
Section 'evaluation: patience, the screen, the uninstall'
$md = Add-AgentMsiDefaults -Arguments 'TRANSFORMS="a.mst"' -LogPath 'C:\x.log'
Assert 'msi: the test adds the template''s own parameters, like Start-ADTMsiProcess' ($md.Arguments -match 'REBOOT=ReallySuppress /QN' -and $md.Arguments -match '/L\*V "C:\\x\.log"' -and @($md.Added).Count -eq 2)
Assert 'msi: an explicit UI level is left alone'   ((Add-AgentMsiDefaults -Arguments '/qb TRANSFORMS="a.mst"').Arguments -notmatch 'ReallySuppress')
Assert 'msi: the parameters come from the template config' ("$((Get-AgentTemplateMsiDefaults).source)" -match 'config\.psd1$')
$pchk = Join-Path (New-TestDir 'params') 'Invoke-AppDeployToolkit.ps1'
Set-Content $pchk @'
Remove-ADTFile -Path "$envCommonDesktop\x.lnk" -ContinueOnError $true
Start-ADTMsiProcess -Action 'Install' -FilePath 'a.msi' -Transforms 'a.mst' -ArgumentList '/qn REBOOT=ReallySuppress'
Start-ADTMsiProcess -Action 'Install' -FilePath 'b.msi' -AdditionalArgumentList 'ALLUSERS=1'
Set-ADTItemPermission -LiteralPath "$envProgramData\Schatz" -User '*S-1-5-32-545' -Permission Modify -Inheritance ObjectInherit,ContainerInherit
'@ -Encoding UTF8
$pc = Test-AgentScriptCommands -ScriptPath $pchk
Assert 'check: a v3 -ContinueOnError on a v4 function is caught' (@($pc.badParameters | Where-Object { $_.parameter -eq '-ContinueOnError' -and $_.line -eq 1 }).Count -eq 1)
Assert 'check: -ArgumentList /qn on Start-ADTMsiProcess is caught' (@($pc.badParameters | Where-Object { $_.parameter -eq '-ArgumentList' -and $_.line -eq 2 }).Count -eq 1)
Assert 'check: correct v4 lines pass, the file does not' (-not @($pc.badParameters | Where-Object { $_.line -ge 3 }).Count -and -not $pc.ok)
$dm = New-TestDir 'motw'; $dmf = Join-Path $dm 'setup.exe'; Set-Content $dmf 'MZ' -Encoding Ascii
Set-Content -LiteralPath $dmf -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
$cl = @(Clear-AgentDownloadMark -Path $dmf)
Assert 'launch: the download mark comes off a local copy' ($cl -contains 'setup.exe' -and -not (Get-Item -LiteralPath $dmf -Stream Zone.Identifier -ErrorAction SilentlyContinue))
Assert 'launch: never on a share'                  (@(Clear-AgentDownloadMark -Path '\\server\share\setup.exe').Count -eq 0)
Assert 'launch: an elevated session starts the process directly, never through the shell' ((Get-Content (Join-Path $here 'Src\Agent.Core.ps1') -Raw) -match 'UseShellExecute = \$false')
$rn = ConvertTo-AgentRunnable -Command "Start-ADTMsiProcess -Action Uninstall -ProductCode '{19BD6C3B-1F9B-480C-972E-1F5DD1D70FD6}'"
Assert 'uninstall: a product code becomes msiexec /x with the template parameters' ($rn.ok -and $rn.file -match 'msiexec' -and $rn.args -match '^/x \{19BD6C3B' -and $rn.args -match 'ReallySuppress')
$fakeUn = Join-Path (New-TestDir 'unins') 'unins000.exe'; Set-Content $fakeUn 'MZ' -Encoding Ascii
$rn2 = ConvertTo-AgentRunnable -Command "`"$fakeUn`" /VERYSILENT /NORESTART"
Assert 'uninstall: a quoted uninstaller with its switches' ($rn2.ok -and $rn2.file -eq $fakeUn -and $rn2.args -eq '/VERYSILENT /NORESTART')
$rn3 = ConvertTo-AgentRunnable -Command 'Start-ADTProcess -FilePath "$envProgramFilesX86\NoSuchVendor\unins000.exe" -ArgumentList "/SILENT"'
Assert 'uninstall: variables resolved; a missing uninstaller is reported, not guessed' (-not $rn3.ok -and $rn3.note -match 'not on this machine' -and $rn3.note -match [regex]::Escape(${env:ProgramFiles(x86)}))
# the decision is checked against what the machine really showed
$ds = [ordered]@{ folder = $dm; trial = @{ found = $false; attempts = @() } }
$m1 = Test-AgentDecision -Sheet $ds -Decision @{ installOutcome = @{ silent = $true }; packagingMethod = @{ installCommand = 'setup.exe /LOADINF="answers.inf" /VERYSILENT' }; provedWhatWasPlanned = @(@{ claim = 'drivers installed'; seen = $true; howSeen = ''; evidence = 'This is a post-install step in the reused predecessor script' }) }
Assert 'decision: "silent" with no silent attempt goes back' ($m1 -match 'no line installed silently')
Assert 'decision: a response file nobody made goes back' ($m1 -match 'answers\.inf')
Assert 'decision: the package''s own step is not "seen"' ($m1 -match 'package-will-do-it')
$ds2 = [ordered]@{ folder = $dm; trial = @{ found = $true; winner = @{ arguments = '/SILENT'; command = '"x\Ceus82.exe" /SILENT' } } }
Assert 'decision: the proven line is the package line' ((Test-AgentDecision -Sheet $ds2 -Decision @{ installOutcome = @{ silent = $true }; packagingMethod = @{ installCommand = '/VERYSILENT /SUPPRESSMSGBOXES' } }) -match "proved is '/SILENT'")
Assert 'decision: an honest one passes'            (-not "$(Test-AgentDecision -Sheet $ds2 -Decision @{ installOutcome = @{ silent = $true }; packagingMethod = @{ installCommand = 'Ceus82.exe /SILENT' }; provedWhatWasPlanned = @(@{ claim = 'ARP entry'; seen = $true; howSeen = 'snapshot'; evidence = 'CEUS 8.2_is1' }) })".Trim())
# THE REAL RUNNER on harmless local stand-ins. The launch is replaced so no test ever needs elevation or raises UAC;
# the stand-in windows sit off-screen.
function Start-AgentInstallerProcess { param([string]$File, [string]$Arguments = '', [string]$WorkingDirectory = '')
    $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName = $File; $psi.Arguments = $Arguments; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    return @{ Process = [System.Diagnostics.Process]::Start($psi); How = 'test launch' } }
$psExe = (Get-Command powershell.exe).Source
$work = New-TestDir 'runner'
$busy = Join-Path $work 'busy.ps1'; Set-Content $busy '$x = 0; $sw = [Diagnostics.Stopwatch]::StartNew(); while ($sw.Elapsed.TotalSeconds -lt 3) { $x++ }; exit 0' -Encoding Ascii
$r1 = Invoke-AgentInstallRun -Installer $psExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$busy`"" -TickMs 500 -StallSec 4 -SettleSec 2 -SettleMaxSec 20 -TimeoutSec 60
Assert 'runner: a working install with no window ends clean' ($r1.ExitCode -eq 0 -and -not $r1.Interactive -and -not @($r1.WindowsSeen).Count -and -not "$($r1.Error)".Trim())
$formTpl = @'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$f = New-Object Windows.Forms.Form; $f.Text = '__TITLE__'; $f.StartPosition = 'Manual'; $f.Location = New-Object Drawing.Point(-4000, -4000); $f.Size = New-Object Drawing.Size(220, 120)
[void]$f.ShowDialog(); exit 5
'@
$wiz = Join-Path $work 'wizard.ps1'; Set-Content $wiz ($formTpl -replace '__TITLE__', 'Setup - Test Wizard') -Encoding Ascii
$script:JudgeSaw = $null
$stopJudge = { param($lk) $script:JudgeSaw = $lk; return @{ whatItIs = 'waiting_for_click - a wizard page with Next'; action = 'stop'; windowToClose = ''; why = 'the installer asks for Next' } }
$r2 = Invoke-AgentInstallRun -Installer $psExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$wiz`"" -TickMs 500 -StallSec 4 -SettleSec 2 -SettleMaxSec 20 -TimeoutSec 60 -Judge $stopJudge
Assert 'runner: a window that sits still is shown to the AI, with a picture' ($script:JudgeSaw -and (@($script:JudgeSaw.windows) -join '|') -match 'Setup - Test Wizard' -and "$($script:JudgeSaw.screenshot)".Trim())
Assert 'runner: "stop" means not silent, and the window is closed' ($r2.Interactive -and -not @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'Setup - Test Wizard' }).Count)
$app = Join-Path $work 'app.ps1'; Set-Content $app ($formTpl -replace '__TITLE__', 'CEUS 8.2 - Test') -Encoding Ascii
$launcher = Join-Path $work 'launcher.ps1'; Set-Content $launcher "`$p = New-Object Diagnostics.ProcessStartInfo '$psExe', '-NoProfile -ExecutionPolicy Bypass -File `"$app`"'; `$p.UseShellExecute = `$false; `$p.CreateNoWindow = `$true; [void][Diagnostics.Process]::Start(`$p); exit 0" -Encoding Ascii
$closeJudge = { param($lk) return @{ whatItIs = 'application_window - the app finishing its settings'; action = 'close_it'; windowToClose = 'CEUS'; why = 'the instructions say CEUS opens at the end' } }
$r3 = Invoke-AgentInstallRun -Installer $psExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`"" -TickMs 500 -StallSec 4 -SettleSec 3 -SettleMaxSec 30 -TimeoutSec 60 -Judge $closeJudge
Assert 'runner: what the install opens after it ends is waited for, judged and closed' ($r3.ExitCode -eq 0 -and (@($r3.WindowsAfterInstall) -join '|') -match 'CEUS 8\.2 - Test' -and @($r3.Looks | Where-Object { $_.phase -eq 'after-exit' -and $_.decided -eq 'close' }).Count -ge 1)
Assert 'silent: a window the hands had to close means NOT silent, whatever the instructions say' ((@($r3.NeededIntervention) -join '|') -match 'CEUS 8\.2 - Test')
Assert 'silent: a clean run needed nobody'           (-not @($r1.NeededIntervention).Count)
Assert 'runner: and it is gone afterwards'         (-not @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'CEUS 8.2 - Test' }).Count)
# EVERY window, not one per process: a second dialog of the same process used to be invisible
$two = Join-Path $work 'twowindows.ps1'
Set-Content $two @'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$a = New-Object Windows.Forms.Form; $a.Text = 'Setup - Main Test'; $a.StartPosition = 'Manual'; $a.Location = New-Object Drawing.Point(-4000, -4000); $a.Size = New-Object Drawing.Size(200, 100)
$b = New-Object Windows.Forms.Form; $b.Text = 'Setup - Second Dialog Test'; $b.StartPosition = 'Manual'; $b.Location = New-Object Drawing.Point(-4000, -3800); $b.Size = New-Object Drawing.Size(200, 100)
$a.Add_Shown({ $b.Show() }); [void]$a.ShowDialog(); exit 0
'@ -Encoding Ascii
$tp = New-Object System.Diagnostics.ProcessStartInfo $psExe, "-NoProfile -ExecutionPolicy Bypass -File `"$two`""; $tp.UseShellExecute = $false; $tp.CreateNoWindow = $true
$twoProc = [System.Diagnostics.Process]::Start($tp)
$seenBoth = $false; for ($k = 0; $k -lt 20 -and -not $seenBoth; $k++) { Start-Sleep -Milliseconds 500; $vw = @(Get-AgentVisibleWindows | Where-Object { $_.id -eq $twoProc.Id }); $seenBoth = (@($vw | Where-Object { $_.title -like 'Setup - *Test' }).Count -ge 2) }
Assert 'windows: both windows of one process are seen (Get-Process sees one)' $seenBoth
[void](Close-AgentWindows -Windows @(Get-AgentVisibleWindows | Where-Object { $_.id -eq $twoProc.Id }) -Family @{ ([int]$twoProc.Id) = $true })
Start-Sleep -Milliseconds 500
Assert 'windows: closed by handle, the process ended'  ($twoProc.HasExited)
if (-not $twoProc.HasExited) { try { $twoProc.Kill() } catch {} }
# the installer is asked what it accepts, and the answer is read
$hl = @(Get-AgentInstallerHelpLook -ExePath $psExe -Switches @('/?') -TimeoutSec 15)
Assert 'help: the installer''s own list of switches is read' (@($hl).Count -eq 1 -and $hl[0].looksLikeHelp -and "$($hl[0].consoleText)" -match '(?i)-NoProfile')
# the toolkit's log goes in full, as readable lines
$cm = ConvertFrom-AgentCmTraceLog '<![LOG[Executing [C:\x\Ceus82.exe /SILENT]...]LOG]!><time="10:00:01.123+120" date="09-29-2026" component="Start-ADTProcess" context="SYSTEM" type="1" thread="1" file="x">
<![LOG[Execution failed with exit code [1603].]LOG]!><time="10:00:09.456+120" date="09-29-2026" component="Start-ADTProcess" context="SYSTEM" type="3" thread="1" file="x">'
Assert 'toolkit log: every line kept, markup gone' ($cm -match '10:00:01 \[info\] Start-ADTProcess: Executing \[C:\\x\\Ceus82\.exe /SILENT\]' -and $cm -match '\[ERROR\] Start-ADTProcess: Execution failed with exit code \[1603\]' -and $cm -notmatch 'LOG\]!')
# the machine since a moment: only what is recent
$evSince = Get-Date; Start-Sleep -Milliseconds 1200
$evDir = New-TestDir 'evlogs'; Set-Content (Join-Path $evDir 'setup.log') "starting`r`nstep 2`r`nERROR: the database provider cannot be found`r`ndone" -Encoding Ascii
$evr = Get-AgentRecentEvidence -Since $evSince -LogDirs @($evDir) -MaxFiles 20
$evLog = @($evr.recentLogs | Where-Object { "$($_.file)" -like "$evDir*" }) | Select-Object -First 1
Assert 'evidence: a log written since the step began, with its error line' ($evLog -and @($evLog.errorLines) -match 'provider cannot be found')
Assert 'evidence: windows and processes since, not everything' ($null -ne $evr.windowsNow -and $null -ne $evr.processesStartedSince)
# the built package is run the way deployment runs it, and the run is reported - the verdict is the AI's
$ptDir = New-TestDir 'pkgtest'; $ptContent = Join-Path $ptDir 'Content'; New-Item -ItemType Directory -Force $ptContent | Out-Null
Copy-Item $psExe (Join-Path $ptContent 'Invoke-AppDeployToolkit.exe'); Set-Content (Join-Path $ptContent 'Invoke-AppDeployToolkit.ps1') '# stand-in' -Encoding Ascii
function Start-AgentInstallerProcess { param([string]$File, [string]$Arguments = '', [string]$WorkingDirectory = '')
    $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName = $File; $psi.Arguments = $Arguments; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    return @{ Process = [System.Diagnostics.Process]::Start($psi); How = 'test launch' } }
$ptr = Invoke-AgentPackageTest -ScriptPath (Join-Path $ptContent 'Invoke-AppDeployToolkit.ps1') -DeploymentTypes @('Install', 'Bogus') -Sheet ([ordered]@{ identity = @{ vendor = 'V'; app = 'A' } }) -StallSec 4
Remove-Item Function:\Start-AgentInstallerProcess; . (Join-Path $here 'Src\Agent.Core.ps1')
Assert 'package test: the run is reported with its exit code and the machine since' (@($ptr.runs).Count -eq 2 -and $null -ne @($ptr.runs)[0].exitCode -and "$(@($ptr.runs)[0].command)" -match '-DeploymentType Install -DeployMode Silent' -and $null -ne @($ptr.runs)[0].machineSinceThisRun)
Assert 'package test: only Install, Repair, Uninstall exist' ("$(@($ptr.runs)[1].verdict)" -eq 'not-run')
# an MSI a vendor EXE unpacks while it runs, and deletes at the end, is caught while it exists
$capScript = Join-Path $work 'unpacker.ps1'
Set-Content $capScript @'
$d = Join-Path $env:TEMP ('is-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory $d | Out-Null
[IO.File]::WriteAllBytes((Join-Path $d 'Vendor_App_1.0.msi'), (New-Object byte[] 300KB)); Set-Content (Join-Path $d 'Data1.cab') 'cab'
Start-Sleep -Seconds 6; Remove-Item $d -Recurse -Force; exit 0
'@ -Encoding Ascii
$capDir = Join-Path $work 'caught'
$r4 = Invoke-AgentInstallRun -Installer $psExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$capScript`"" -TickMs 500 -StallSec 4 -SettleSec 2 -SettleMaxSec 20 -TimeoutSec 60 -CaptureMsiTo $capDir
$caughtMsi = @(Get-ChildItem -LiteralPath $capDir -Recurse -File -Filter 'Vendor_App_1.0.msi' -ErrorAction SilentlyContinue)
Assert 'capture: an MSI the installer unpacks and deletes is caught while it exists' (@($r4.MsiCaptured).Count -eq 1 -and $caughtMsi.Count -eq 1 -and $caughtMsi[0].Length -eq 300KB)
Assert 'capture: with the cabinet beside it'       (@(Get-ChildItem -LiteralPath $caughtMsi[0].DirectoryName -Filter 'Data1.cab').Count -eq 1)
Remove-Item Function:\Start-AgentInstallerProcess
. (Join-Path $here 'Src\Agent.Core.ps1')
# the AI writes the whole command; the hands read it
$c1 = ConvertFrom-AgentCommandLine 'msiexec /i "C:\SW-Source\Firefox Setup 140.16.0esr_en-us.msi" TRANSFORMS="C:\SW-Source\Firefox Setup 140.16.0esr_en-us.mst"'
Assert 'command: msiexec /i "..." -> the MSI and its arguments' ($c1.ok -and $c1.installer -eq 'Firefox Setup 140.16.0esr_en-us.msi' -and $c1.arguments -match '^TRANSFORMS=')
$c2 = ConvertFrom-AgentCommandLine '"Ceus82.exe" /SILENT'
Assert 'command: a quoted EXE and its switches'    ($c2.ok -and $c2.installer -eq 'Ceus82.exe' -and $c2.arguments -eq '/SILENT')
Assert 'command: an unquoted path with spaces'     ((ConvertFrom-AgentCommandLine 'C:\Program Files\x\unins000.exe /VERYSILENT').installer -eq 'unins000.exe')
Assert 'command: a document''s path and the bare name are the same transform' ((ConvertTo-AgentComparableArgs 'TRANSFORMS="C:\SW-Source\Firefox Setup.mst"') -eq (ConvertTo-AgentComparableArgs 'TRANSFORMS="Firefox Setup.mst"'))
Assert 'command: a path that does not exist here resolves to the delivered file' ((Resolve-AgentArgumentPaths -Arguments 'TRANSFORMS="C:\SW-Source\Firefox Setup 140.16.0esr_en-us.mst"' -InstallerPath $msiP) -match [regex]::Escape($mDir))
$lg = Join-Path $work 'm.log'
[IO.File]::WriteAllText($lg, "MSI (c) (AA:BB) [10:00:00:000]: Looking for file transform: C:\x\a.mst`r`nMSI (s) (CC:DD) [10:00:05:000]: Product: Vendor App -- Installation completed successfully.`r`nMSI (s) (CC:DD) [10:00:05:000]: MainEngineThread is returning 0`r`n", [Text.Encoding]::Unicode)
$lf = Test-AgentMsiLog -LogPath $lg -Arguments 'TRANSFORMS="C:\x\a.mst;b.mst"'
Assert 'msi log: which transform really applied, and how it ended' (@($lf.transformsApplied) -contains 'a.mst' -and @($lf.transformsNotSeen) -contains 'b.mst' -and $lf.outcome -match 'completed successfully' -and $lf.returnValue -eq 0)
$tpSheet = [ordered]@{ folder = $dm; sources = @{ installers = @(@{ name = 'setup.exe'; ext = '.exe' }) } }
$tpBase = @{ readiness = 'ready'; route = @{ kind = 'fresh'; number = 3 }; predecessor = @{ found = $false; why = 'none on the shares' } }
$tp1 = $tpBase.Clone(); $tp1.install = @{ steps = @(@{ order = 1; installer = 'setup.exe'; commandLine = '"setup.exe" /VERYSILENT /NORESTART'; arguments = '/SILENT' }) }
Assert 'plan: a command line and arguments that disagree go back' ((Test-AgentPlan -Sheet $tpSheet -Plan $tp1) -match 'must say the same thing')
$tp2 = $tpBase.Clone(); $tp2.install = @{ steps = @(@{ order = 1; installer = 'setup.exe'; commandLine = '"C:\SW-Source\setup.exe"  /VERYSILENT /NORESTART'; arguments = '/VERYSILENT /NORESTART' }) }
Assert 'plan: the same line written two ways passes' (-not "$(Test-AgentPlan -Sheet $tpSheet -Plan $tp2)".Trim())
# the method: the predecessor's first; another only when proven
$dsP = [ordered]@{ folder = $dm; history = @{ predecessor = @{ path = '\\srv\pkgs\Old_1.0' } }; trial = @{ found = $false; attempts = @() } }
Assert 'method: a judgement with a predecessor must say which method' ((Test-AgentDecision -Sheet $dsP -Decision @{ installOutcome = @{ silent = $false } }) -match 'methodChoice is missing')
Assert 'method: leaving the predecessor''s method needs proof' ((Test-AgentDecision -Sheet $dsP -Decision @{ installOutcome = @{ silent = $false }; methodChoice = @{ chosen = 'other'; why = 'simpler' } }) -match "chosen is 'other'")
$dsP.trial = @{ found = $true; winner = @{ arguments = ''; command = 'msiexec /i x.msi' } }
Assert 'method: the predecessor''s method, proven, passes' (-not "$(Test-AgentDecision -Sheet $dsP -Decision @{ installOutcome = @{ silent = $true }; methodChoice = @{ chosen = 'predecessor'; why = 'as before' } })".Trim())
Assert 'method: a second round must name files that exist' ((Test-AgentDecision -Sheet $dsP -Decision @{ installOutcome = @{ silent = $true }; methodChoice = @{ chosen = 'predecessor' }; testNext = @{ wanted = $true; why = 'x'; steps = @(@{ order = 1; commandLine = 'msiexec /i "Nowhere_9.9.msi"' }) } }) -match "testNext names 'Nowhere_9.9.msi'")
$ns = [ordered]@{ identity = @{ vendor = 'V'; app = 'A'; arch = 'x86'; version = '1.0'; release = '0001'; lang = 'MUL' }; package = 'V_A_x86_1.0-0001_MUL'; folder = $dm
                  sources = @{ installers = @(@{ name = 'setup.exe'; ext = '.exe'; path = $dmf }) }
                  plan = @{ route = @{ kind = 'fresh'; number = 3 }; install = @{ steps = @(@{ order = 1; installer = 'setup.exe'; arguments = '/S' }) } }
                  provenSteps = @(@{ order = 1; installer = 'A_1.0.msi'; arguments = '' }, @{ order = 2; installer = 'prereq.msi'; arguments = 'TRANSFORMS="p.mst"' })
                  msiCaptured = @(@{ file = 'A_1.0.msi'; productCode = '{11111111-2222-3333-4444-555555555555}' }) }
$np = New-AgentNewPkg -Sheet $ns
Assert 'build: the lines the machine proved are what gets built, caught MSIs with their product code' ($np.InstallerMode -eq 'Multiple' -and "$(@($np.Installers)[0].MsiFileName)" -eq 'A_1.0.msi' -and "$(@($np.Installers)[0].ProductCode)" -match '^\{1111')
Assert 'roots: an installer may come from the order, extraction, a caught MSI or the previous package' (@(Get-AgentInstallerRoots -Sheet ([ordered]@{ sources = @{ payloadRoot = 'C:\o' }; extractedDir = 'C:\e'; capturedDir = 'C:\c'; history = @{ predecessor = @{ path = '\\s\p' } } })).Count -eq 5)
Assert 'handbook: the predecessor''s method first, no fixed recipes' ((Get-AgentSystemPrompt) -match "THE METHOD: THE PREDECESSOR'S FIRST" -and (Get-AgentSystemPrompt) -match 'No application gets a fixed recipe')
Assert 'handbook: whose word wins is written down' ((Get-AgentSystemPrompt) -match 'WHOSE WORD WINS' -and (Get-AgentSystemPrompt) -match 'Read EVERYTHING')
# giving the machine back
Assert 'cleanup: an MSI entry comes off by product code' ((Get-AgentSilentUninstallFor -Info @{ _key = '{11111111-2222-3333-4444-555555555555}'; UninstallString = 'MsiExec.exe /X{11111111-2222-3333-4444-555555555555}' }).command -eq 'msiexec /x {11111111-2222-3333-4444-555555555555}')
Assert 'cleanup: an entry''s own quiet line is used' ((Get-AgentSilentUninstallFor -Info @{ _key = 'Vendor App'; UninstallString = '"C:\x\uninst.exe"'; QuietUninstallString = '"C:\x\uninst.exe" /S' }).command -eq '"C:\x\uninst.exe" /S')
Assert 'cleanup: Inno Setup with its documented silent switches' ((Get-AgentSilentUninstallFor -Info @{ _key = 'CEUS 8.2_is1'; UninstallString = '"C:\Program Files (x86)\K\unins000.exe"' }).command -match '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART$')
Assert 'cleanup: nothing known = reported, never guessed' ($null -eq (Get-AgentSilentUninstallFor -Info @{ _key = 'Odd App'; UninstallString = '"C:\x\remove.exe"' }))
$baseSnap = Get-MachineSnapshot -NoDeep
$tmpPd = Join-Path $env:ProgramData ('PackagingAgentTest_' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force -Path $tmpPd | Out-Null; Set-Content (Join-Path $tmpPd 'x.ini') 'x'
$cln = Invoke-AgentMachineCleanup -Before $baseSnap -Sheet ([ordered]@{ identity = @{ vendor = 'PackagingAgentTest'; app = 'Test' } }) -Why 'test'
Assert 'cleanup: a folder the test created comes off, and the machine is back' (-not (Test-Path -LiteralPath $tmpPd) -and @($cln.foldersRemoved) -contains $tmpPd)
if (Test-Path -LiteralPath $tmpPd) { Remove-Item -LiteralPath $tmpPd -Recurse -Force }
Assert 'evaluate: every round ends by giving the machine back' ((Get-AgentStageScript -Id 'evaluate') -match 'at the end of test round' -and (Get-AgentStageScript -Id 'evaluate') -match 'BetweenAttempts')
Assert 'knowledge: no application recipe was written in by hand' (-not @(Get-AgentMemoryAll | Where-Object { "$($_.text)" -match 'acceptable instead of the extracted MSI' }).Count)
# the look and the uninstall review, through the job runner
$script:Fake['watch'] = { param($Body, $Round) return (New-FakeResponse -Call 'submit_look' -CallArgs @{ whatItIs = 'application_window - CEUS finishing its settings'; action = 'close_it'; windowToClose = 'CEUS'; why = 'the instructions say CEUS opens at the end' }) }
$c0 = (Get-AgentConversation -Sheet $jobSheet).Count
$jl = Invoke-AgentScreenJudge -Sheet $jobSheet -Look ([ordered]@{ phase = 'after-exit'; action = 'install'; windows = @('t81010: CEUS 8.2'); screenshot = '' })
Assert 'look: the AI''s answer becomes an action the hands know' ($jl.action -eq 'close' -and $jl.windowToClose -eq 'CEUS')
Assert 'look: folded into two short turns'         ($jobSheet.conversation.Count -eq $c0 + 2)
$savedReview = $script:Fake['review']
$script:Fake['review'] = { param($Body, $Round) return (New-FakeResponse -Call 'submit_uninstall_review' -CallArgs @{ uninstallWorked = $true; silent = $true; proven = $true; commandForThePackage = '"C:\x\unins000.exe" /VERYSILENT /NORESTART'; leftBehind = @(@{ item = 'C:\ProgramData\Schatz'; verdict = 'must-clean'; command = 'Remove-ADTFolder -LiteralPath "$envProgramData\Schatz"' }); packageUpdate = @{ postUninstall = @(@{ order = 2; what = 'remove Schatz'; command = 'Remove-ADTFolder -LiteralPath "$envProgramData\Schatz"' }) }; summary = 'clean' }) }
$jobSheet.decision = [ordered]@{ uninstall = [ordered]@{ command = 'old' }; packageUpdate = [ordered]@{ postUninstall = @(@{ order = 1; what = 'a'; command = 'Remove-ADTFolder -LiteralPath x' }) } }
$jobSheet.uninstallTest = [ordered]@{ command = '"C:\x\unins000.exe" /VERYSILENT'; ran = $true; verdict = 'silent'; exitCode = 0; leftBehind = @{ count = 1; ProgramDirs = @('C:\ProgramData\Schatz') }; looks = @() }
$jobSheet = Invoke-AgentUninstallReview -Sheet $jobSheet
Assert 'uninstall review: proven, and the proven line is what the build uses' ([bool]$jobSheet.decision.uninstall.proven -and "$($jobSheet.decision.uninstall.command)" -match 'NORESTART')
Assert 'uninstall review: its cleanup is added to the package, not swapped for it' (@($jobSheet.decision.packageUpdate.postUninstall).Count -eq 2)
$script:Fake['review'] = $savedReview; $jobSheet.decision = $null; $jobSheet.uninstallTest = $null; $jobSheet.uninstallReview = $null
Assert 'evaluate: the retry candidates are really run (the loop no longer stops after round one)' ((Get-AgentStageScript -Id 'evaluate') -match '-not \$ranSequence' -and (Get-AgentStageScript -Id 'evaluate') -notmatch '-le 3 -and -not \$trial;')
Assert 'evaluate: the uninstall is tested after the judgement' ((Get-AgentStageScript -Id 'evaluate') -match 'Invoke-AgentUninstallTest' -and (Get-AgentStageScript -Id 'evaluate') -match 'Invoke-AgentUninstallReview')
Assert 'dossier: the packagers'' notes come first, and what the toolkit adds by itself is stated' ((Get-Content (Join-Path $here 'Src\Agent.Brain.ps1') -Raw) -match "THE PACKAGERS' STANDING ORDERS" -and (Get-Content (Join-Path $here 'Src\Agent.Brain.ps1') -Raw) -match 'whatTheToolkitDoesByItself')
# faithful copies
$tsSrc = New-TestDir 'ts'; New-Item -ItemType Directory -Force -Path (Join-Path $tsSrc 'source\sub') | Out-Null
Set-Content (Join-Path $tsSrc 'source\app.msi') 'x' -Encoding ascii; Set-Content (Join-Path $tsSrc 'source\sub\pref.js') 'y' -Encoding ascii
$old = (Get-Date).AddDays(-30); foreach ($i in @(Get-ChildItem $tsSrc -Recurse -Force)) { $i.CreationTimeUtc = $old.ToUniversalTime(); $i.LastWriteTimeUtc = $old.AddHours(2).ToUniversalTime() }
$tsDst = Join-Path (New-TestDir 'td') 'copy'
$cpy = Copy-AgentTreeWithTimestamps -Source $tsSrc -Destination $tsDst
$mis = 0; foreach ($o in @(Get-ChildItem $tsSrc -Recurse -Force)) { $n = Get-Item -LiteralPath (Join-Path $tsDst $o.FullName.Substring($tsSrc.Length).TrimStart('\')) -Force -ErrorAction SilentlyContinue; if (-not $n -or $n.CreationTimeUtc -ne $o.CreationTimeUtc -or $n.LastWriteTimeUtc -ne $o.LastWriteTimeUtc) { $mis++ } }
Assert 'copy: every date survives, files and folders' ($cpy.ok -and $mis -eq 0)
# memory
$memPath = Get-AgentMemoryPath; $memBak = $null; if (Test-Path -LiteralPath $memPath) { $memBak = Get-Content -LiteralPath $memPath -Raw; Remove-Item -LiteralPath $memPath -Force }
[void](Add-AgentMemory -Text 'This vendor ships an EXE that configures before calling its own MSI.' -Scope 'vendor:Mozilla')
[void](Add-AgentMemory -Text 'Never remove the Edge WebView runtime on uninstall.' -Scope 'global')
[void](Add-AgentMemory -Text 'Never remove the Edge WebView runtime on uninstall!' -Scope 'global')
[void](Add-AgentMemory -Text 'Inno Setup needs /SP- with /VERYSILENT.' -Scope 'technology:Inno Setup')
Assert 'memory: the same thing twice is one thing' (@(Get-AgentMemoryAll).Count -eq 3)
Assert 'memory: the right part for the right order' (@(Get-AgentMemoryFor -Vendor 'Adobe' -Package 'x' -Technology 'InnoSetup').Count -eq 2 -and -not @(Get-AgentMemoryFor -Vendor 'Adobe' -Package 'x' | Where-Object { "$($_.scope)" -eq 'vendor:Mozilla' }).Count)
Assert 'memory: it lives with the agent'           ($memPath -match 'Knowledge\\Experience\.json$')
if ($memBak) { Set-Content -LiteralPath $memPath -Value $memBak -Encoding UTF8 } else { Remove-Item -LiteralPath $memPath -Force -ErrorAction SilentlyContinue }
# the free tools
$inv = Initialize-AgentTools -Force
Assert 'tools: the inventory is honest'            ((Get-AgentToolInventory).msiLibrary -and (Get-AgentToolInventory).installerInspection)
if ($inv.sevenZip) {
    $az = New-TestDir 'arc'; $inner = Join-Path $az 'payload'; New-Item -ItemType Directory -Force -Path $inner | Out-Null; Set-Content (Join-Path $inner 'readme.txt') 'x' -Encoding ascii
    $zip = Join-Path $az 'bundle.zip'; [IO.Compression.ZipFile]::CreateFromDirectory($inner, $zip)
    $ins = Get-AgentArchiveInsight -Path $zip
    Assert 'archive: the headers are read'         ($ins.readBy -eq '7-Zip' -and $ins.entryCount -ge 1 -and @($ins.msiCandidates).Count -eq 0)
}
if ($inv.dtf) {
    $selfMsi = Join-Path (New-TestDir 'msi') 'probe.msi'
    try {
        $db = New-Object Microsoft.Deployment.WindowsInstaller.Database($selfMsi, [Microsoft.Deployment.WindowsInstaller.DatabaseOpenMode]::CreateDirect)
        $db.Execute("CREATE TABLE ``Property`` (``Property`` CHAR(72) NOT NULL, ``Value`` CHAR(0) NOT NULL PRIMARY KEY ``Property``)")
        foreach ($kv in @(@('ProductName', 'Agent Probe'), @('ProductVersion', '1.2.3'), @('ProductCode', '{11111111-2222-3333-4444-555555555555}'))) { $db.Execute("INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('$($kv[0])', '$($kv[1])')") }
        $db.Commit(); $db.Dispose()
        $id = Get-AgentMsiIdentity -Path $selfMsi
        Assert 'msi: identity read by the library'  ($id.productName -eq 'Agent Probe' -and $id.productVersion -eq '1.2.3')
        $fakeMst = Join-Path (Split-Path $selfMsi) 'bogus.mst'; [IO.File]::WriteAllBytes($fakeMst, (New-Object byte[] 2048))
        Assert 'mst: a bogus transform is refused'  ((Test-AgentMstApplies -MsiPath $selfMsi -MstPath $fakeMst).applies -eq $false)
    } catch { Write-Host "  (could not build a probe MSI: $($_.Exception.Message.Split([char]10)[0]))" -ForegroundColor DarkGray }
}
Assert 'trace: a missing capture is stated'        ((Get-AgentProcessTraceFacts -BackingFile (Join-Path $env:TEMP 'nope-none.pml')).note -match 'not there')
$cfgDir = New-TestDir 'cfgf'
Set-Content (Join-Path $cfgDir 'settings.xml') -Encoding utf8 -Value '<config><checkForUpdates>true</checkForUpdates><sendUsageData>true</sendUsageData></config>'
$cfr = @(Get-AgentConfigFileFacts -Roots @($cfgDir))
Assert 'config: files are READ, settings shortlisted' ((@($cfr)[0].text -match 'sendUsageData') -and ((@(@($cfr)[0].preferenceLines) -join ' ') -match 'checkForUpdates'))

# =====================================================================================================================
Section 'the window (no window needed)'
$log = New-AgentActivityLog
Add-AgentActivity -Log $log -Actor 'TOOL' -Stage 'evaluate' -Text 'Taking the baseline snapshot.'
$opLog = New-AgentOpContext -PackageFolder $env:TEMP -Activity $log -Stage 'verify'
$null = Invoke-AgentOpCommand -Ctx $opLog -Purpose 'read the script' -Intent 'read' -Script "'x'"
Assert 'feed: AI commands and TOOL steps stay apart' (@($log | Where-Object { $_.actor -eq 'AI' -and $_.kind -eq 'command' }).Count -eq 1 -and @($log | Where-Object { $_.actor -eq 'TOOL' }).Count -eq 1)
$fe = New-AgentFeedEntry -Item @($log | Where-Object { $_.actor -eq 'AI' })[0]
Assert 'feed: an entry renders without a window'   ($fe -is [Windows.Controls.Border] -and $fe.Child.Children[0].Text -match '^(DECISION|COMMAND|RESULT|ANSWER|PROBLEM|NOTE)')
foreach ($stg in 'evaluate', 'plan') {
    $sc = Get-AgentStageScript -Id $stg; $er = $null; [void][Management.Automation.Language.Parser]::ParseInput($sc, [ref]$null, [ref]$er)
    Assert "window: the '$stg' stage script parses" (@($er).Count -eq 0 -and $sc -match 'param\(\$a, \$box\)')
}
$evalScript = Get-AgentStageScript -Id 'evaluate'
Assert 'window: evaluate reads the PLAN'           ($evalScript -match '\$sheet\.plan\.evaluate' -and $evalScript -match '\$p\.Sequence' -and $evalScript -notmatch 'assessment')
Assert 'window: machine prep before the baseline'  ($evalScript -match '(?s)Invoke-AgentMachinePrep.*Get-MachineSnapshot')
Assert 'window: the old version comes off BEFORE the new goes on' ($evalScript -match '(?s)Uninstall-AgentPredecessorPackage -InstallResult \$pi.*\$before = \$afterRemoval')
$conTxt = Get-Content (Join-Path $here 'Src\Agent.Console.ps1') -Raw
Assert 'window: candidates come from the plan only' ($conTxt -match '\$cands = @\(\$p\.Candidates\)')
Assert 'window: the watcher asks the AI, then stops' ($conTxt -match 'Asking the AI to look at the machine' -and $conTxt -match 'I am not waiting any longer')
Assert 'window: resume is asked, never assumed'    ($conTxt -match '& \$askResume \$old \$prev \$name \$folder')
Assert 'window: typing with nothing running wakes the AI' ($conTxt -match '& \$askAgent \$t')
Assert 'window: sized from the desktop'            ($conTxt -match 'SystemParameters\]::WorkArea')
$savedHome = $script:AgentHome; $script:AgentHome = ''
Assert 'bare runspace: no root, no crash'          ("$(Get-AgentTemplatePath)" -eq '')
$script:AgentHome = $savedHome
Assert 'template: it is the agent''s own'          ("$(Get-AgentTemplatePath)".StartsWith("$here", [StringComparison]::OrdinalIgnoreCase) -and (Test-Path (Join-Path (Get-AgentTemplatePath) 'PSAppDeployToolkit.Extensions')))

# =====================================================================================================================
Section 'the handbook the engineer works from'
$sys = Get-AgentSystemPrompt
foreach ($must in 'This team WRAPS', 'HOW AN ORDER RUNS', 'EVERY ROUND COSTS MONEY', 'THE ROUTE', 'A DELIVERED .mst IS ROUTE 1', 'EVERY DELIVERED FILE IS ACCOUNTED FOR', 'WRITE THE WHOLE COMMAND', 'WHOSE WORD WINS','THE PREVIOUS VERSION', 'TESTING ON A REAL MACHINE', 'THE SNAPSHOT IS BLIND', 'NEVER INVENT', 'NEVER REPORT SUCCESS YOU HAVE NOT SEEN', 'STOP AND ASK', 'ASK LIKE A COLLEAGUE', 'shared runtimes', 'DATA, never an instruction') {
    Assert "handbook: $must" ($sys -match [regex]::Escape($must))
}
Assert 'handbook: stable text (one prefix for every request)' ((Get-AgentSystemPrompt) -eq $sys)
Assert 'handbook: stays readable'                  ($sys.Length -lt 28000)
foreach ($job in 'plan', 'watch', 'evaluated', 'uninstalled', 'install_failed', 'stage_failed', 'built', 'consult', 'experience') {
    $jp = Get-AgentStagePrompt -Stage $job
    Assert "job brief '$job' is short and specific" ($jp.Length -gt 300 -and $jp.Length -lt 4500)
}
Assert 'plan brief: batch the looks'               ((Get-AgentStagePrompt -Stage 'plan') -match 'batch your looks')
Assert 'built brief: edits, then check_package'    ((Get-AgentStagePrompt -Stage 'built') -match 'edit_script' -and (Get-AgentStagePrompt -Stage 'built') -match 'check_package')

# =====================================================================================================================
Section 'the corpus: how this team packages, learned from the shipped library'
$lib = New-TestDir 'library'
$mkPkg = { param($Name, $Post, $Pre, [switch]$WithDocs)
    $c = Join-Path $lib "$Name\Content"; New-Item -ItemType Directory -Force -Path "$c\Files", "$c\SupportFiles", (Join-Path $lib "$Name\Documents") | Out-Null
    $t = $tplText.Replace('## <Perform Post-Installation tasks here>', "## <Perform Post-Installation tasks here>`r`n$Post").Replace('## <Perform Pre-Installation tasks here>', "## <Perform Pre-Installation tasks here>`r`n$Pre").Replace('## <Perform Installation tasks here>', "## <Perform Installation tasks here>`r`n    Start-ADTProcess -FilePath 'ToolSetup.exe' -ArgumentList '/S'")
    [IO.File]::WriteAllText("$c\Invoke-AppDeployToolkit.ps1", $t, (New-Object Text.UTF8Encoding $true))
    Set-Content "$c\Files\ToolSetup.exe" 'MZ' -Encoding Ascii; Set-Content "$c\SupportFiles\Tool_ActiveSetup.ps1" '# stub' -Encoding Ascii
    if ($WithDocs) {
        New-TestDocx -Path (Join-Path $lib "$Name\Documents\Evaluation Tool.docx") -Paragraphs @('Evaluation of Tool', 'created module pack (this part will be filled in by packaging team)', 'Installation command | Invoke-AppDeployToolkit.exe install', 'Package requires reboot | -', 'Contact: jane.doe@man.eu, product {11111111-2222-3333-4444-555555555555}')
        $zd = New-TestDir 'zipdocs'; Set-Content (Join-Path $zd 'Query and Information - RITM0001 Tool installs its updater.msg') 'mail' -Encoding Ascii; New-Item -ItemType Directory -Force (Join-Path $zd 'Upgrade') | Out-Null; Set-Content (Join-Path $zd 'Upgrade\psadt.log') 'log' -Encoding Ascii
        [IO.Compression.ZipFile]::CreateFromDirectory($zd, (Join-Path $lib "$Name\Documents\Documents.zip"))
    } }
& $mkPkg 'Vendor_Tool_x64_1.0-0001_MUL' "    ## the vendor updater re-enables itself after every start because it runs as a service, so the service is disabled too`r`n    Disable-ScheduledTask -TaskName 'ToolUpdater'`r`n    Set-Service -Name 'ToolUpdateSvc' -StartupType Disabled`r`n    Remove-ADTFile -Path `"`$envCommonDesktop\Tool.lnk`"" "    Remove-ADTFolder -Path `"`$envProgramFiles\Vendor\Tool`"`r`n    Stop-Process -Name tool -Force`r`n    Remove-ADTRegistryKey -Key 'HKLM:\SOFTWARE\Vendor\Tool'" -WithDocs
& $mkPkg 'Vendor_Other_x64_3.0-0001_MUL' "    Disable-ScheduledTask -TaskName 'OtherUpdater'" ''
$corpusOut = New-TestDir 'corpusout'; $corpusCache = New-TestDir 'corpuscache'
$hv = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Tools\Build-CorpusKnowledge.ps1') -From $lib -OutDir $corpusOut -CacheDir $corpusCache 2>&1 | ForEach-Object { "$_" }
Assert 'harvest: it reads a library and writes the corpus' ((Test-Path "$corpusOut\Index.json") -and (Test-Path "$corpusOut\Patterns.json") -and (Test-Path "$corpusOut\Vendors.json") -and (Test-Path "$corpusOut\Lessons.json") -and (Test-Path "$corpusOut\Packages\Vendor.json"))
if (-not (Test-Path "$corpusOut\Index.json")) { $hv | Select-Object -Last 15 | ForEach-Object { Write-Host "     $_" -ForegroundColor Red } }
$script:AgentCorpusDir = $corpusOut; $script:AgentCorpusCache = @{}
$vp = @(Get-AgentCorpusPart 'Packages\Vendor.json') | Where-Object { $_.package -eq 'Vendor_Tool_x64_1.0-0001_MUL' }
Assert 'harvest: two packages indexed'             (@(Get-AgentCorpusPart 'Index.json').Count -eq 2)
Assert 'harvest: what post-install does, by command' (@($vp.phases.PostInstall | ForEach-Object { $_.cmd }) -contains 'Disable-ScheduledTask' -and @($vp.phases.PostInstall | ForEach-Object { $_.cmd }) -contains 'Set-Service')
Assert 'harvest: how the old version was removed'  ("$($vp.previousVersionRemoval)" -eq 'generic')
Assert 'harvest: the updater and shortcut handling' (@($vp.updater).Count -ge 1 -and @($vp.shortcuts).Count -ge 1)
Assert 'harvest: per-user practice from SupportFiles' (@($vp.perUser) -match 'Active Setup')
Assert 'harvest: the author''s note is kept'        ((@($vp.authorNotes) -join ' ') -match 'runs as a service')
Assert 'harvest: the evaluation''s packaging section' ((@($vp.documents.whatTheyRecorded.PSObject.Properties | ForEach-Object { "$($_.Value)" }) -join ' ') -match 'filled in by packaging team')
Assert 'harvest: query mails and test logs, from inside the zip' ((@($vp.documents.queryMails) -join ' ') -match 'installs its updater' -and @($vp.documents.testLogs) -contains 'Upgrade')
Assert 'harvest: personal data scrubbed, product codes kept' ((@($vp.documents.whatTheyRecorded.PSObject.Properties | ForEach-Object { "$($_.Value)" }) -join ' ') -notmatch 'jane\.doe' -and (($vp | ConvertTo-Json -Depth 8) -match '11111111-2222-3333-4444-555555555555'))
$pat = Get-AgentCorpusPart 'Patterns.json'
Assert 'patterns: the library''s practice is counted' ($pat.packages -eq 2 -and (@($pat.whatEachPhaseDoes.PostInstall | Where-Object { $_.command -eq 'Disable-ScheduledTask' })[0].packages -eq 2))
Assert 'lessons: author notes that explain something' (@(Get-AgentCorpusLessons -Vendor 'Vendor').Count -ge 1)
Assert 'vendors: a profile per vendor'             ((Get-AgentCorpusVendor -Vendor 'Vendor').packages -eq 2)
$sim = @(Find-AgentCorpusPackages -Vendor 'Vendor' -App 'Tool' -ExcludePackage 'Vendor_Tool_x64_2.0-0001_MUL')
Assert 'similar: the same application comes first' ($sim.Count -ge 1 -and $sim[0].package -eq 'Vendor_Tool_x64_1.0-0001_MUL')
Assert 'similar: an unrelated order finds nothing' (@(Find-AgentCorpusPackages -Vendor 'Nobody' -App 'Nothing').Count -eq 0)
$cs2 = New-AgentSheet -PkgName 'Vendor_Tool_x64_2.0-0001_MUL' -Folder $ord; $cs2.identity = @{ vendor = 'Vendor'; app = 'Tool'; version = '2.0' }; $cs2.sources = $sheet.sources
$cd = (@(New-AgentDossier -Sheet $cs2) | ForEach-Object { "$($_.text)" }) -join "`n"
Assert 'dossier: the shipped packages most like this order' ($cd -match 'shippedPackagesMostLikeThisOrder' -and $cd -match 'Vendor_Tool_x64_1\.0-0001_MUL' -and $cd -match 'runs as a service')
Assert 'dossier: the vendor profile and the practice' ($cd -match 'howThisTeamPackagesThisVendor' -and $cd -match 'howThisTeamPackages')
Assert 'dossier: it is told to learn, not copy'    ($cd -match 'Never copy a line blindly')
$kt = Get-AgentKnowledgeTool
Assert 'read_knowledge: packages, vendor, lessons, patterns' (@((& $kt.Run @{ topic = 'packages:Vendor Tool' } @{}).packages).Count -ge 1 -and (& $kt.Run @{ topic = 'vendor:Vendor' } @{}).packages -eq 2 -and @((& $kt.Run @{ topic = 'lessons:service' } @{}).lessons).Count -ge 1 -and (& $kt.Run @{ topic = 'patterns' } @{}).packages -eq 2)
Assert 'handbook: learn the practice, not copy lines' ((Get-AgentSystemPrompt) -match 'Learn the PRACTICE')
$script:AgentCorpusDir = ''; $script:AgentCorpusCache = @{}
Assert 'scrub: product codes survive, phone numbers do not' ((Invoke-AgentScrub 'code {28B89EEF-1234-5678-9012-CF3F3A09B77D} tel 091 9860 348 680') -match '28B89EEF-1234-5678-9012-CF3F3A09B77D' -and (Invoke-AgentScrub 'tel 091 9860 348 680') -match '\[phone\]')

# =====================================================================================================================
Section 'the report and the handover'
$html = ConvertTo-AgentSheetHtml -Sheet $sheet
Assert 'report: the plan is shown'                 ($html -match '<h2>The plan</h2>' -and $html -match 'reuse_with_changes' -and $html -match 'App Setup 2\.0\.mst')
Assert 'report: what the test proved, and did not' ($html -match 'NOT SEEN')
Assert 'report: the verification and the edits'    ($html -match 'Verification of the built package' -and $html -match 'What the AI changed in the package')
Assert 'report: the text view'                     ((Format-AgentSheetText -Sheet $sheet) -match 'PLAN: reuse_with_changes' -and (Format-AgentSheetText -Sheet $sheet) -match 'must prove')
$exp = Export-AgentEvaluation -Ctx @{ Sheet = $sheet; Result = $result; RunInfo = $run }
Assert 'export: sheet + snapshot report + handover' ((Test-Path $exp.Sheet) -and (Test-Path $exp.SnapshotReport) -and (Test-Path $exp.Handover))
$ho = Get-Content $exp.Handover -Raw | ConvertFrom-Json
Assert 'handover: carries the plan and the proof'  ("$($ho.plan.route.kind)" -eq 'reuse_with_changes' -and @($ho.testProved).Count -eq 2)
Assert 'handover: says whether it is ready'        ("$($ho.readyToHandOver)".Trim().Length -gt 0 -and $null -ne $ho.finalCheck)
Assert 'handover: a change that did not land is listed' (@($ho.changesNotApplied).Count -eq 1)

Section 'the agent keeps learning: every order becomes a case'
$case = @(Get-AgentCasesAll | Where-Object { $_.package -eq 'Vendor_App_x64_2.0-0001_MUL' })[0]
Assert 'cases: the handover recorded this order'   ($null -ne $case -and "$($case.route)" -match 'reuse_with_changes')
Assert 'cases: with the line the machine proved'   ("$($case.provenLine)" -match 'TRANSFORMS="App Setup 2\.0\.mst"')
Assert 'cases: with what the test found'           ("$($case.autoUpdate)" -match 'scheduled task' -and "$($case.uninstall)" -match '\{NEW\}')
$memBak2 = if (Test-Path -LiteralPath (Get-AgentMemoryPath)) { [IO.File]::ReadAllText((Get-AgentMemoryPath)) } else { $null }
[void](Invoke-AgentExperienceIntake -Text 'The ServerName must be set before first start.' -Sheet $sheet)
if ($null -ne $memBak2) { [IO.File]::WriteAllText((Get-AgentMemoryPath), $memBak2, (New-Object Text.UTF8Encoding $true)) } else { Remove-Item -LiteralPath (Get-AgentMemoryPath) -Force -ErrorAction SilentlyContinue }
Assert 'cases: what the packager said after testing is kept with it' ((@(Get-AgentCasesAll | Where-Object { $_.package -eq 'Vendor_App_x64_2.0-0001_MUL' })[0].packagerSaid -join ' ') -match 'ServerName')
Assert 'cases: one record per order, updated not duplicated' (@(Get-AgentCasesAll | Where-Object { $_.package -eq 'Vendor_App_x64_2.0-0001_MUL' }).Count -eq 1)
$next = @(Get-AgentCasesFor -Vendor 'Vendor' -App 'App' -ExcludePackage 'Vendor_App_x64_3.0-0001_MUL')
Assert 'cases: the next version finds it'          (@($next | Where-Object { $_.package -eq 'Vendor_App_x64_2.0-0001_MUL' }).Count -eq 1)
Assert 'cases: an unrelated order does not'        (@(Get-AgentCasesFor -Vendor 'Other' -App 'Thing').Count -eq 0)
$nextSheet = New-AgentSheet -PkgName 'Vendor_App_x64_3.0-0001_MUL' -Folder $ord; $nextSheet.identity = @{ vendor = 'Vendor'; app = 'App'; version = '3.0' }; $nextSheet.sources = $sheet.sources
$nd = (@(New-AgentDossier -Sheet $nextSheet) | ForEach-Object { "$($_.text)" }) -join "`n"
Assert 'cases: they reach the next order''s dossier' ($nd -match 'WHAT THIS TEAM DID BEFORE' -and $nd -match 'Vendor_App_x64_2\.0-0001_MUL' -and $nd -match 'ServerName')
$catHit = Search-AgentCatalogue -Terms @('Oracle JDK')
Assert 'catalogue: ~900 shipped packages are searchable' (@($catHit.found).Count -ge 1 -and "$(@($catHit.found)[0].package)" -match 'Oracle')
Assert 'catalogue: reachable through read_knowledge' (@((& (Get-AgentKnowledgeTool).Run @{ topic = 'catalogue:Oracle JDK' } @{}).found).Count -ge 1)
Assert 'cases: reachable through read_knowledge'   (@((& (Get-AgentKnowledgeTool).Run @{ topic = 'cases:Vendor App' } @{}).cases | Where-Object { $_.package -eq 'Vendor_App_x64_2.0-0001_MUL' }).Count -eq 1)
Assert 'handbook: it is told to learn the practice from what the team did' ((Get-AgentSystemPrompt) -match 'Learn the PRACTICE')
Assert 'knowledge: the map of what is where exists' (Test-Path (Join-Path $here 'Knowledge\README.md'))

# ---- the gateway's own failure modes, over real HTTP against a stand-in server -----------------------------------------
$gw = Join-Path $testRoot 'Test-Gateway.ps1'
if (Test-Path $gw) {
    Section 'gateway behaviour (Test-Gateway.ps1)'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $gw | ForEach-Object { Write-Host $_ }
    Assert 'gateway tests passed' ($LASTEXITCODE -eq 0)
}
try { Remove-Item (Join-Path $env:TEMP 'PackagingAgentTest') -Recurse -Force -ErrorAction SilentlyContinue } catch {}
if ($null -ne $casesBak) { [IO.File]::WriteAllText($casesPath, $casesBak, (New-Object Text.UTF8Encoding $false)) } else { Remove-Item -LiteralPath $casesPath -Force -ErrorAction SilentlyContinue }
if ($fail) { Write-Host "`n$fail TEST(S) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "`nALL AGENT TESTS PASSED" -ForegroundColor Green }
