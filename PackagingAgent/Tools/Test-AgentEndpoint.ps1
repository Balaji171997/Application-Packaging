##############################################################
# Test-AgentEndpoint.ps1  -  "does my API key work from THIS machine?"  (run before the agent, nothing is stored)
#   powershell -ExecutionPolicy Bypass -File .\Test-AgentEndpoint.ps1
#   ... -BaseUrl https://gateway.company.com/v1 -Model gemini-2.5-flash-lite        (key is always asked hidden)
# Checks in order: name resolution -> proxy -> HTTPS -> key accepted -> model answers -> FUNCTION CALLING works
# (the agent needs tool calls, not just chat). Prints what each step means, and the model names the gateway lists.
##############################################################
[CmdletBinding()]
param([string]$BaseUrl, [string]$Model, [string]$Tool, [switch]$Save, [string]$Key, [string]$TokenUrl, [string]$ClientId, [string]$ClientSecret, [switch]$NoToken)   # -Key/-ClientSecret only for scripted tests; interactively they are typed hidden
$agentRoot = Split-Path -Parent $(if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path })   # PackagingAgent (this script lives in Tools\)
function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
# minimal library: Core.ps1 for Write-Log/Get-WorkPath (any tool folder), then the agent's client
if (-not $Tool) { $parent = Split-Path -Parent $agentRoot; $Tool = @(Get-ChildItem -LiteralPath $parent, $agentRoot -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'Core.ps1') } | Select-Object -First 1 | ForEach-Object { $_.FullName }) }
if ($Tool -and (Test-Path "$Tool\Core.ps1")) { . "$Tool\Core.ps1"; Initialize-Config (Join-Path $Tool 'settings.json') } else { function Write-Log { param($m, $l) }; function Get-WorkPath { param($s) Join-Path $env:TEMP "PackagingAgent\$s" }; function Get-Setting { param($n, $d) $d } }
. "$agentRoot\Src\Agent.Gemini.ps1"
$script:AgentSettingsPath = Join-Path $agentRoot 'agent.settings.json'
Say ''; Say '  PACKAGING AGENT - endpoint check' Cyan; Say ''
$BaseUrl = "$BaseUrl".Trim("'", '"', ' ')
if (-not $BaseUrl -and -not $PSBoundParameters.ContainsKey('BaseUrl')) { $BaseUrl = Read-Host '  Endpoint URL (Enter = Google Gemini API directly; a sk-... key needs the gateway URL it came with)' }
if (-not $Model)   { $Model = Read-Host "  Model name (Enter = $(Get-AgentModel))" }
$plain = $Key
if (-not $plain) { $sec = Read-Host '  API key (typed hidden, not stored)' -AsSecureString; $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)) }
if ("$plain".Trim()) { Set-AgentApiKey -Key $plain }
Set-AgentEndpoint -BaseUrl $BaseUrl -Model $Model
if (-not $NoToken) {
    if (-not $TokenUrl -and -not $PSBoundParameters.ContainsKey('ClientSecret')) { $TokenUrl = Read-Host '  Token URL (Enter = none; only for gateways behind an identity provider, e.g. https://idp.../protocol/openid-connect/token)' }
    if ($TokenUrl) {
        if (-not $ClientId) { $ClientId = Read-Host '  Client ID' }
        if (-not $ClientSecret) { $s2 = Read-Host '  Client secret (typed hidden, memory only)' -AsSecureString; $ClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2)) }
        Set-AgentAuth -TokenUrl $TokenUrl -ClientId $ClientId -ClientSecret $ClientSecret
    }
}
if (-not "$plain".Trim() -and -not "$ClientSecret".Trim()) { Say '  no key and no client secret - nothing to test' Yellow; exit 1 }
$k = "$plain".Trim()
if ($k) { Say ("  key format: {0}... ({1} chars) -> {2}" -f $k.Substring(0, [Math]::Min(6, $k.Length)), $k.Length, $(if ($k -match '^AIza') { 'Google Gemini API key' } elseif ($k -match '^sk-') { 'OpenAI-style GATEWAY key (needs the gateway URL)' } else { 'unknown style' })) DarkGray }
if ($TokenUrl -and $TokenUrl -match '(?i)openid-connect/token|/oauth2?/token') { Say '  token URL recognised as an OAuth/OIDC token endpoint - the AI endpoint itself must be a DIFFERENT url (the base URL above)' DarkGray }
if ($BaseUrl -match '(?i)openid-connect/token|/oauth2?/token') { Say '  WARNING: the endpoint URL you gave is a TOKEN endpoint (identity provider), not the AI API. Put it under Token URL and enter the AI base URL (…/v1) as endpoint.' Yellow }
Say ''
$r = Test-GeminiConnection
foreach ($s in $r.Steps) { Say "  $s" $(if ($s -match 'FAILED|NOT resolvable|meaning') { 'Yellow' } elseif ($s -match '^chat: OK') { 'Green' } else { 'Gray' }) }
if (-not $r.Ok) { Say ''; Say "  RESULT: $(if ($r.Error -match 'token check only') { 'identity provider checked; the AI endpoint URL is still needed (see the token claims above for the gateway name)' } else { 'not working from here - see the "meaning" line above.' })" $(if ($r.Error -match 'token check only') { 'Yellow' } else { 'Red' }); if (-not $PSBoundParameters.ContainsKey('BaseUrl') -and -not $Key) { Read-Host '  Enter to close' | Out-Null }; exit 2 }
# function calling - the agent's whole flow depends on it
Say ''; Say '  function-calling test...' Gray
try {
    $decl = New-AgentFunctionDeclaration -Name 'submit_test' -Description 'Submit the answer.' -Parameters @{ type = 'OBJECT'; properties = @{ answer = @{ type = 'STRING' }; number = @{ type = 'INTEGER' } }; required = @('answer') }
    $rr = Invoke-GeminiChat -System 'Answer ONLY by calling submit_test.' -Contents @(@{ role = 'user'; parts = @(@{ text = 'Call submit_test with answer="ok" and number=7.' }) }) -Tools @($decl) -Name 'tool-test' -Temperature 0
    $fc = @($rr.FunctionCalls) | Where-Object { $_.Name -eq 'submit_test' } | Select-Object -First 1
    if ($fc) { Say "  function calling: OK (answer=$($fc.Args.answer), number=$($fc.Args.number))" Green } else { Say "  function calling: the model answered with TEXT instead of a tool call - the agent will not work reliably on this endpoint: '$($rr.Text)'" Yellow }
} catch { Say "  function calling: FAILED - $($_.Exception.Message)" Red }
Say ''; Say "  RESULT: endpoint + key + model work from this machine.   ($(Format-AgentUsage))" Green
if ($Save -or (-not $Key -and (Read-Host '  Remember URL + model in agent.settings.json (key is NOT saved)? [y/N]') -match '^y')) { Set-AgentEndpoint -BaseUrl $BaseUrl -Model $Model -Remember; Say '  saved.' Green }
