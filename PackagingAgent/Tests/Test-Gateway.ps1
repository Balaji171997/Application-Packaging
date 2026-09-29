##############################################################
# Test-Gateway.ps1 - reproduce the VW LLMaaS "HTTP 200 with choices: []" answer and prove the agent survives it.
#   The stand-in gateway answers EXACTLY like the real one did: empty choices while tools are attached,
#   and a normal JSON answer once the agent retries without tools.
##############################################################
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $(if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path })   # PackagingAgent\
. "$repo\Engine\Core.ps1"
. "$repo\Src\Agent.Gemini.ps1"
$script:Settings = @{ WorkRoot = (Join-Path $env:TEMP 'PackagingAgentTest') }; $script:WorkRoot = $null
Initialize-Log

$fail = 0
function Assert($name, $cond) { if ($cond) { Write-Host "PASS $name" -ForegroundColor Green } else { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ } }

# ---- the stand-in gateway (raw TCP so it needs no admin rights) -------------------------------------------------
$port = 18099
$server = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
$server.Start()
$state = [hashtable]::Synchronized(@{ WithTools = 0; WithoutTools = 0; Stop = $false })

$rs = [runspacefactory]::CreateRunspace(); $rs.Open()
$rs.SessionStateProxy.SetVariable('server', $server)
$rs.SessionStateProxy.SetVariable('state', $state)
$ps = [PowerShell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript({
    function Send-Reply($stream, $json) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $head  = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
        $hb = [Text.Encoding]::ASCII.GetBytes($head)
        $stream.Write($hb, 0, $hb.Length); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
    }
    while (-not $state.Stop) {
        try {
            if (-not $server.Pending()) { Start-Sleep -Milliseconds 50; continue }
            $client = $server.AcceptTcpClient(); $stream = $client.GetStream()
            $buf = New-Object byte[] 262144; $text = ''; $deadline = (Get-Date).AddSeconds(8); $continued = $false
            while ((Get-Date) -lt $deadline) {
                if ($stream.DataAvailable) { $n = $stream.Read($buf, 0, $buf.Length); $text += [Text.Encoding]::UTF8.GetString($buf, 0, $n) }
                elseif ($text -match "`r`n`r`n") {
                    # .NET sends "Expect: 100-continue" and waits for our go-ahead before sending the body
                    if (-not $continued -and $text -match '(?i)Expect:\s*100-continue') {
                        $continued = $true
                        $cont = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 100 Continue`r`n`r`n")
                        $stream.Write($cont, 0, $cont.Length); $stream.Flush(); Start-Sleep -Milliseconds 80; continue
                    }
                    $len = 0; if ($text -match '(?i)Content-Length:\s*(\d+)') { $len = [int]$Matches[1] }
                    $bodyNow = ($text -split "`r`n`r`n", 2)[1]
                    if ($len -eq 0 -or ([Text.Encoding]::UTF8.GetByteCount("$bodyNow")) -ge $len) { break }
                    Start-Sleep -Milliseconds 20
                }
                else { Start-Sleep -Milliseconds 20 }
            }
            if ($text -match '"tools"') {
                $state.WithTools++
                # what VW LLMaaS actually sent: 200, no candidate, prompt billed, zero completion tokens
                Send-Reply $stream '{"id":"x","object":"chat.completion","model":"gemini-2.5-flash-lite","choices":[],"usage":{"prompt_tokens":9224,"completion_tokens":0,"total_tokens":9224}}'
            } else {
                $state.WithoutTools++
                $payload = '{\"installOutcome\":{\"silent\":true},\"items\":[{\"category\":\"Programs\",\"label\":\"Firefox\",\"action\":\"keep\"}]}'
                Send-Reply $stream ('{"id":"y","object":"chat.completion","model":"gemini-2.5-flash-lite","choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"' + $payload + '"}}],"usage":{"prompt_tokens":9000,"completion_tokens":120,"total_tokens":9120}}')
            }
            $stream.Close(); $client.Close()
        } catch {}
    }
})
$h = $ps.BeginInvoke()

try {
    $script:PkgAgent.ApiKey = 'sk-test'
    $script:PkgAgent.Overrides = @{ Provider = 'openai'; BaseUrl = "http://127.0.0.1:$port/v1"; AuthMode = 'key'
                                    Model = 'gemini-2.5-flash-lite'; FallbackModels = @('gemini-2.5-flash'); TimeoutSec = 20 }
    $tools = @(@{ name = 'submit_decision'; description = 'Submit the classification.'
                  parameters = @{ type = 'OBJECT'; properties = @{ installOutcome = @{ type = 'OBJECT'; properties = @{ silent = @{ type = 'BOOLEAN' } } }
                                                                   items = @{ type = 'ARRAY'; items = @{ type = 'OBJECT'; properties = @{ category = @{ type = 'STRING' }; label = @{ type = 'STRING' }; action = @{ type = 'STRING' } } } } } } })

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-GeminiChat -System 'You classify snapshots.' -Contents @(@{ role = 'user'; parts = @(@{ text = 'the snapshot diff' }) }) -Tools $tools -Name 'classify' -Temperature 0
    $sw.Stop()

    Assert 'the stage survived an empty-choices gateway' ($null -ne $r)
    Assert 'a function call was produced anyway'         (@($r.FunctionCalls).Count -eq 1 -and $r.FunctionCalls[0].Name -eq 'submit_decision')
    Assert 'the payload was parsed'                      ($r.FunctionCalls[0].Args.installOutcome.silent -eq $true -and @($r.FunctionCalls[0].Args.items).Count -eq 1)
    Assert 'marked as the json fallback'                 ($r.FinishReason -eq 'json-fallback')
    Assert 'it retried, then changed model, then dropped the tools' ($state.WithTools -ge 4 -and $state.WithoutTools -eq 1)
    Write-Host ("  gateway saw: $($state.WithTools) request(s) with tools, $($state.WithoutTools) without   ({0:N1}s)" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
}
finally {
    $state.Stop = $true
    try { $ps.EndInvoke($h) } catch {}
    try { $ps.Dispose(); $rs.Close(); $rs.Dispose() } catch {}
    try { $server.Stop() } catch {}
}

if ($fail) { Write-Host "`n$fail TEST(S) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "`nNO-CANDIDATE TEST PASSED" -ForegroundColor Green }
