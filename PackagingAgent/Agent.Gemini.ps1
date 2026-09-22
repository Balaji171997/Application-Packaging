##############################################################
# Agent.Gemini.ps1
# Gemini API client for the Packaging Agent - PowerShell 5.1, Invoke-RestMethod only (no SDK, no Python).
#   * generateContent with function declarations (tool calling), optional JSON response schema, inline images
#   * API key: SESSION ONLY by default (typed in the tool, never written anywhere); optional Windows Credential
#     Manager store; GEMINI_API_KEY env var for the CLI. settings.json never carries the key.
#   * retries with backoff on 429/5xx, model fallback on 404 (a retired model id), token + cost meter, and a
#     per-session AUDIT LOG (every request/response as JSON under WorkRoot\AI\) so a decision is always traceable.
#   * $script:PkgAgent.Transport can be replaced by a scriptblock (recorded responses) so tests run OFFLINE.
# Nothing here decides anything - it only talks to the model. Decisions live in Agent.Core.ps1.
##############################################################
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

$script:PkgAgent = @{
    ApiKey = $null; KeySource = ''; Transport = $null
    Calls = 0; TokensIn = 0; TokensOut = 0; TokensThought = 0; CostUSD = 0.0
    AuditDir = $null; AuditSeq = 0; LastError = ''
    ModelUsed = ''
}
# List prices (USD per 1M tokens: input, output) - approximate, editable via settings.json -> AI.Prices.
$script:AgentDefaultPrices = @{
    'gemini-3.5-flash-lite' = @(0.30, 2.50)
    'gemini-3.5-flash'      = @(1.50, 7.50)
    'gemini-2.5-flash-lite' = @(0.10, 0.40)
    'gemini-2.5-flash'      = @(0.30, 2.50)
}
$script:AgentEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models'

# Effective AI config = defaults overlaid with settings.json -> "AI". Returned as a hashtable (never $null).
function Get-AgentConfig {
    $d = [ordered]@{
        Enabled = $true
        Provider = 'gemini'                # 'gemini' = Google's own API (key AIza...) | 'openai' = an OpenAI-compatible GATEWAY (key sk-..., needs BaseUrl)
        BaseUrl = ''                       # openai provider: e.g. https://ai-gateway.company.com/v1  (the /chat/completions path is appended)
        ExtraHeaders = @{}                 # openai provider: extra HTTP headers some gateways need (e.g. api-key)
        # Gateways behind an identity provider (Keycloak/OIDC): client credentials -> access token (Bearer), the sk-key in an extra header.
        TokenUrl = ''                      # e.g. https://idp.company.com/auth/realms/<realm>/protocol/openid-connect/token
        ClientId = ''                      # ClientSecret is NEVER in a file - typed at runtime only (Set-AgentAuth)
        Scope = ''
        AuthMode = 'auto'                  # auto | key (Bearer sk-key) | token (Bearer access token) | token+key (Bearer token + sk-key in ApiKeyHeader)
        ApiKeyHeader = 'x-api-key'         # header carrying the sk-key in token+key mode (some gateways: api-key, X-Gateway-APIKey ...)
        Model = 'gemini-3.5-flash-lite'
        FallbackModels = @('gemini-2.5-flash-lite')
        Models = @{}                       # per task override: extract / decide / classify / review
        MaxStepsPerStage = 12; MaxCostPerPackageUSD = 5.0
        SendScreenshots = $true; MaxImages = 12; MaxImageEdge = 1280
        GroundingSearch = $false
        Temperature = 0.2
        Thinking = $null                   # e.g. @{ thinkingLevel = 'low' } (Gemini 3) or @{ thinkingBudget = 0 } (2.5)
        CredentialTarget = 'PackagingAgent-Gemini'
        Proxy = ''
        TimeoutSec = 180
        Prices = @{}
        TrustedThumbprints = @()           # pin exact server certificates (SHA1 thumbprints) when the gateway's CA is not installed on this machine
        FastLane = @{ MinorUpdate = $true; KnownVendorPredecessor = $true }
    }
    $h = @{}; foreach ($k in $d.Keys) { $h[$k] = $d[$k] }
    $cfg = $null
    # The agent's OWN settings file (PackagingAgent\agent.settings.json, key "AI") wins; a tool's settings.json "AI" block is the fallback.
    if ($script:AgentSettingsPath -and (Test-Path -LiteralPath $script:AgentSettingsPath)) {
        try { $j = (Get-Content -LiteralPath $script:AgentSettingsPath -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json; if ($j.AI) { $cfg = $j.AI } } catch { Write-Log "AI: agent.settings.json unreadable: $($_.Exception.Message)" Warning }
    }
    try { if (-not $cfg -and (Get-Command Get-Setting -ErrorAction SilentlyContinue)) { $cfg = Get-Setting 'AI' } } catch {}
    if ($cfg) {
        $props = if ($cfg -is [hashtable]) { $cfg.GetEnumerator() | ForEach-Object { @{ Name = $_.Key; Value = $_.Value } } } else { $cfg.PSObject.Properties }
        foreach ($p in $props) {
            $v = $p.Value
            if ($v -is [System.Management.Automation.PSCustomObject]) { $t = @{}; foreach ($q in $v.PSObject.Properties) { $t[$q.Name] = $q.Value }; $v = $t }
            $h[$p.Name] = $v
        }
    }
    # RUNTIME overrides (typed in the key dialog / verifier for this session): endpoint URL, model, provider - never written unless asked
    if ($script:PkgAgent.Overrides) { foreach ($k in @($script:PkgAgent.Overrides.Keys)) { if ("$($script:PkgAgent.Overrides[$k])".Trim()) { $h[$k] = $script:PkgAgent.Overrides[$k] } } }
    # pinned server certificates (AI.TrustedThumbprints) take effect as soon as the config is read
    if ($h.TrustedThumbprints -and -not $script:AgentPinsApplied) { $script:AgentPinsApplied = $true; try { Set-AgentTrustedThumbprints -Thumbprints @($h.TrustedThumbprints) } catch { Write-Log "AI: pinning failed: $($_.Exception.Message)" Warning } }
    return $h
}
# Session endpoint: URL + model (+ provider) as typed at runtime. -Remember writes them (NOT the key) to agent.settings.json.
function Set-AgentEndpoint {
    param([string]$BaseUrl, [string]$Model, [string]$Provider, [switch]$Remember)
    if (-not $script:PkgAgent.Overrides) { $script:PkgAgent.Overrides = @{} }
    $u = "$BaseUrl".Trim(); $m = "$Model".Trim(); $p = "$Provider".Trim().ToLower()
    if (-not $p) { $p = if ($u) { 'openai' } elseif ("$(Get-AgentApiKey)" -match '^sk-') { 'openai' } else { 'gemini' } }
    if ($u) { $script:PkgAgent.Overrides.BaseUrl = $u }; if ($m) { $script:PkgAgent.Overrides.Model = $m }; $script:PkgAgent.Overrides.Provider = $p
    Write-Log "AI: endpoint set for this session - provider=$p base=$(if ($u) { $u } else { '(google)' }) model=$(if ($m) { $m } else { '(default)' })"
    if ($Remember -and $script:AgentSettingsPath) {
        try {
            $j = if (Test-Path -LiteralPath $script:AgentSettingsPath) { (Get-Content -LiteralPath $script:AgentSettingsPath -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json } else { [pscustomobject]@{} }
            if (-not $j.AI) { $j | Add-Member -NotePropertyName AI -NotePropertyValue ([pscustomobject]@{}) -Force }
            $ov = $script:PkgAgent.Overrides
            foreach ($pair in @(@('Provider', $p), @('BaseUrl', $u), @('Model', $m), @('TokenUrl', "$($ov.TokenUrl)"), @('ClientId', "$($ov.ClientId)"), @('AuthMode', "$($ov.AuthMode)"), @('ApiKeyHeader', "$($ov.ApiKeyHeader)"))) { if ($pair[1]) { $j.AI | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force } }   # never the key or the client secret
            $j | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $script:AgentSettingsPath -Encoding utf8 -Force
            Write-Log "AI: endpoint remembered in $script:AgentSettingsPath (key is NOT in there)."
        } catch { Write-Log "AI: could not save the endpoint: $($_.Exception.Message)" Warning }
    }
}
function Test-AgentEnabled { $c = Get-AgentConfig; return [bool]$c.Enabled }

# Model for a TASK ('extract','decide','classify','review'): AI.Models.<task> if set, else AI.Model.
function Get-AgentModel {
    param([string]$Task = '')
    $c = Get-AgentConfig
    if ($Task -and $c.Models) {
        $m = if ($c.Models -is [hashtable]) { $c.Models[$Task] } else { $c.Models.$Task }
        if ("$m".Trim()) { return "$m".Trim() }
    }
    return "$($c.Model)".Trim()
}

#region API key -----------------------------------------------------------------------------------------------
# Windows Credential Manager (generic credential) via advapi32 - so an OPTIONAL "remember on this machine" is DPAPI-
# protected per user, never a file. Compiled once; a compile failure just disables the remember option.
function Initialize-AgentCredApi {
    if ('PB.CredMan' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
namespace PB {
public static class CredMan {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL { public uint Flags; public uint Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public uint CredentialBlobSize; public IntPtr CredentialBlob;
    public uint Persist; public uint AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredRead(string target, uint type, uint flags, out IntPtr cred);
  [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredWrite(ref CREDENTIAL cred, uint flags);
  [DllImport("advapi32.dll", EntryPoint="CredDeleteW", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredDelete(string target, uint type, uint flags);
  [DllImport("advapi32.dll")] static extern void CredFree(IntPtr cred);
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return null;
    try { CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
          if (c.CredentialBlobSize == 0) return ""; return Marshal.PtrToStringUni(c.CredentialBlob, (int)c.CredentialBlobSize / 2); }
    finally { CredFree(p); } }
  public static bool Write(string target, string user, string secret) {
    byte[] b = Encoding.Unicode.GetBytes(secret); CREDENTIAL c = new CREDENTIAL();
    c.Type = 1; c.TargetName = target; c.UserName = user; c.CredentialBlobSize = (uint)b.Length; c.Persist = 2;
    c.CredentialBlob = Marshal.AllocHGlobal(b.Length); Marshal.Copy(b, 0, c.CredentialBlob, b.Length);
    try { return CredWrite(ref c, 0); } finally { Marshal.FreeHGlobal(c.CredentialBlob); } }
  public static bool Delete(string target) { return CredDelete(target, 1, 0); }
}}
'@ -ErrorAction Stop
        return $true
    } catch { Write-Log "Credential Manager API unavailable: $($_.Exception.Message)" Warning; return $false }
}
# Set the key for THIS SESSION (in memory). -Remember also stores it in Credential Manager (user opt-in).
function Set-AgentApiKey {
    param([string]$Key, [switch]$Remember, [switch]$Forget)
    $k = "$Key".Trim()
    if ($Forget) {
        $script:PkgAgent.ApiKey = $null; $script:PkgAgent.KeySource = ''
        if (Initialize-AgentCredApi) { try { [void][PB.CredMan]::Delete((Get-AgentConfig).CredentialTarget) } catch {} }
        Write-Log 'AI: API key cleared (session + Credential Manager).'
        return
    }
    if (-not $k) { return }
    $script:PkgAgent.ApiKey = $k; $script:PkgAgent.KeySource = 'session'
    if ($Remember -and (Initialize-AgentCredApi)) {
        try { if ([PB.CredMan]::Write((Get-AgentConfig).CredentialTarget, 'api', $k)) { $script:PkgAgent.KeySource = 'credential-manager'; Write-Log 'AI: API key stored in Windows Credential Manager (this user, this machine).' } }
        catch { Write-Log "AI: could not store the key: $($_.Exception.Message)" Warning }
    } else { Write-Log 'AI: API key set for this session only (not stored).' }
}
# Resolve the key: session -> GEMINI_API_KEY env -> Credential Manager. $null when none (caller prompts the user).
function Get-AgentApiKey {
    if ("$($script:PkgAgent.ApiKey)".Trim()) { return $script:PkgAgent.ApiKey }
    if ("$env:GEMINI_API_KEY".Trim()) { $script:PkgAgent.ApiKey = "$env:GEMINI_API_KEY".Trim(); $script:PkgAgent.KeySource = 'environment'; return $script:PkgAgent.ApiKey }
    if (Initialize-AgentCredApi) {
        try { $v = [PB.CredMan]::Read((Get-AgentConfig).CredentialTarget); if ("$v".Trim()) { $script:PkgAgent.ApiKey = "$v".Trim(); $script:PkgAgent.KeySource = 'credential-manager'; return $script:PkgAgent.ApiKey } } catch {}
    }
    return $null
}
function Test-AgentHasKey { return [bool]("$(Get-AgentApiKey)".Trim()) }
#endregion

#region Audit + cost ---------------------------------------------------------------------------------------------
# One audit folder per agent RUN (package). Every request/response lands there as NNN-<name>.json; image bytes are
# replaced by their size so the log stays readable and small.
function Start-AgentAudit {
    param([string]$Name = 'session')
    $safe = ("$Name" -replace '[\\/:*?"<>|]', '_'); if (-not $safe) { $safe = 'session' }
    $dir = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath ("AI\$safe") } else { Join-Path $env:TEMP "PackagingAgent\$safe" }
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
    $script:PkgAgent.AuditDir = $dir; $script:PkgAgent.AuditSeq = 0
    return $dir
}
function Get-AgentAuditDir { if (-not $script:PkgAgent.AuditDir) { [void](Start-AgentAudit) }; return $script:PkgAgent.AuditDir }
function Write-AgentAudit {
    param([string]$Name, $Request, $Response, [string]$Error = '')
    try {
        $dir = Get-AgentAuditDir
        $script:PkgAgent.AuditSeq++
        $f = Join-Path $dir ('{0:D3}-{1}.json' -f $script:PkgAgent.AuditSeq, ($Name -replace '[^\w\-]', '_'))
        $rec = [ordered]@{ when = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); name = $Name; model = $script:PkgAgent.ModelUsed
                           request = (ConvertTo-AgentAuditSafe $Request); response = $Response; error = $Error
                           usage = @{ calls = $script:PkgAgent.Calls; tokensIn = $script:PkgAgent.TokensIn; tokensOut = $script:PkgAgent.TokensOut; costUSD = [math]::Round($script:PkgAgent.CostUSD, 4) } }
        $rec | ConvertTo-Json -Depth 30 | Out-File -LiteralPath $f -Encoding utf8 -Force
    } catch {}
}
# Deep-copy a request body with inlineData.data replaced by "<N bytes>".
function ConvertTo-AgentAuditSafe {
    param($Obj)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $Obj.Keys) {
            if ("$k" -eq 'inlineData' -and $Obj[$k] -is [System.Collections.IDictionary]) {
                $o[$k] = @{ mimeType = $Obj[$k].mimeType; data = "<$("$($Obj[$k].data)".Length) base64 chars>" }
            } else { $o[$k] = ConvertTo-AgentAuditSafe $Obj[$k] }
        }
        return $o
    }
    if ($Obj -is [array] -or ($Obj -is [System.Collections.IList] -and $Obj -isnot [string])) { return ,@(foreach ($i in $Obj) { ConvertTo-AgentAuditSafe $i }) }   # comma keeps a 1-element array an array
    return $Obj
}
function Add-AgentUsage {
    param($Usage, [string]$Model)
    if (-not $Usage) { return }
    $in  = [int]$Usage.promptTokenCount; $out = [int]$Usage.candidatesTokenCount; $th = [int]$Usage.thoughtsTokenCount
    $script:PkgAgent.Calls++; $script:PkgAgent.TokensIn += $in; $script:PkgAgent.TokensOut += ($out + $th); $script:PkgAgent.TokensThought += $th
    $prices = $script:AgentDefaultPrices.Clone()
    $c = Get-AgentConfig
    if ($c.Prices) { $pp = if ($c.Prices -is [hashtable]) { $c.Prices.GetEnumerator() | ForEach-Object { @{ Name=$_.Key; Value=$_.Value } } } else { $c.Prices.PSObject.Properties }
                     foreach ($p in $pp) { $prices["$($p.Name)"] = @([double]$p.Value[0], [double]$p.Value[1]) } }
    $pr = $prices["$Model"]; if (-not $pr) { $pr = @(0.30, 2.50) }
    $script:PkgAgent.CostUSD += ($in / 1e6) * $pr[0] + (($out + $th) / 1e6) * $pr[1]
}
function Get-AgentUsageSummary {
    return @{ Calls = $script:PkgAgent.Calls; TokensIn = $script:PkgAgent.TokensIn; TokensOut = $script:PkgAgent.TokensOut; CostUSD = [math]::Round($script:PkgAgent.CostUSD, 4); Model = $script:PkgAgent.ModelUsed; KeySource = $script:PkgAgent.KeySource }
}
function Reset-AgentUsage { $script:PkgAgent.Calls = 0; $script:PkgAgent.TokensIn = 0; $script:PkgAgent.TokensOut = 0; $script:PkgAgent.TokensThought = 0; $script:PkgAgent.CostUSD = 0.0 }
# Take over the usage a BACKGROUND runspace accumulated (it comes back in the sheet's audit block). -Add sums instead of replacing.
function Set-AgentUsage { param($Summary, [switch]$Add)
    if (-not $Summary) { return }
    if (-not $Add) { Reset-AgentUsage }
    $script:PkgAgent.Calls += [int]$Summary.Calls; $script:PkgAgent.TokensIn += [int]$Summary.TokensIn; $script:PkgAgent.TokensOut += [int]$Summary.TokensOut; $script:PkgAgent.CostUSD += [double]$Summary.CostUSD
    if ("$($Summary.Model)".Trim()) { $script:PkgAgent.ModelUsed = "$($Summary.Model)" }
}
function Get-AgentKeySource { return "$($script:PkgAgent.KeySource)" }
function Format-AgentUsage {
    $u = Get-AgentUsageSummary
    return ('{0} call(s) · {1:N0} in / {2:N0} out tokens · ${3:N3}' -f $u.Calls, $u.TokensIn, $u.TokensOut, $u.CostUSD)
}
#endregion

#region Parts ------------------------------------------------------------------------------------------------------
function New-AgentTextPart { param([string]$Text) return @{ text = "$Text" } }
# Inline image part. Re-encodes through System.Drawing (EMF/BMP/GIF -> PNG; JPEG kept) and downsizes to MaxEdge so a
# 4K wizard screenshot does not cost 4K tokens. Returns $null when the file cannot be read as an image.
function New-AgentImagePart {
    param([Parameter(Mandatory)][string]$Path, [int]$MaxEdge = 1280)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $img = [System.Drawing.Image]::FromFile($Path)
        try {
            $w = $img.Width; $h = $img.Height
            $scale = 1.0; $m = [Math]::Max($w, $h); if ($MaxEdge -gt 0 -and $m -gt $MaxEdge) { $scale = $MaxEdge / $m }
            $nw = [Math]::Max(1, [int]($w * $scale)); $nh = [Math]::Max(1, [int]($h * $scale))
            $bmp = New-Object System.Drawing.Bitmap $nw, $nh
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.Clear([System.Drawing.Color]::White)
            $g.DrawImage($img, 0, 0, $nw, $nh); $g.Dispose()
            $ms = New-Object IO.MemoryStream
            $isJpg = ($img.RawFormat.Guid -eq [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid)
            if ($isJpg) { $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg); $mime = 'image/jpeg' } else { $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $mime = 'image/png' }
            $bmp.Dispose()
            return @{ inlineData = @{ mimeType = $mime; data = [Convert]::ToBase64String($ms.ToArray()) } }
        } finally { $img.Dispose() }
    } catch { Write-Log "AI: image skipped ($([IO.Path]::GetFileName($Path))): $($_.Exception.Message)" Warning; return $null }
}
# Function declaration in Gemini's shape. $Parameters is an OpenAPI-style schema hashtable.
function New-AgentFunctionDeclaration {
    param([Parameter(Mandatory)][string]$Name, [string]$Description = '', [hashtable]$Parameters)
    $d = @{ name = $Name; description = $Description }
    if ($Parameters) { $d.parameters = $Parameters }
    return $d
}
#endregion

#region Transport ----------------------------------------------------------------------------------------------------
# POST one generateContent request. Returns the parsed response object. Throws on a non-retryable failure.
function Invoke-GeminiRequest {
    param([Parameter(Mandatory)][hashtable]$Body, [Parameter(Mandatory)][string]$Model, [string]$Name = 'call')
    $c = Get-AgentConfig
    if ($script:PkgAgent.Transport) {                      # test double: scriptblock (Body, Model, Name) -> response object
        $r = & $script:PkgAgent.Transport $Body $Model $Name
        $script:PkgAgent.ModelUsed = $Model
        Add-AgentUsage -Usage $r.usageMetadata -Model $Model
        Write-AgentAudit -Name $Name -Request $Body -Response $r
        return $r
    }
    $key = Get-AgentApiKey
    if (-not $key) { throw 'No Gemini API key. Enter it in the tool (Assistant > API key) or set GEMINI_API_KEY.' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    # corporate proxy (VDI): let the system proxy authenticate with the signed-in user, like a browser does
    try { $dp = [Net.WebRequest]::DefaultWebProxy; if ($dp -and -not $dp.Credentials) { $dp.Credentials = [Net.CredentialCache]::DefaultCredentials } } catch {}
    $json  = $Body | ConvertTo-Json -Depth 40 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $models = @($Model) + @($c.FallbackModels | Where-Object { $_ -and $_ -ne $Model })
    $lastErr = $null
    foreach ($m in $models) {
        $url = "$script:AgentEndpoint/$m`:generateContent"
        for ($attempt = 1; $attempt -le 4; $attempt++) {
            try {
                $p = @{ Uri = $url; Method = 'Post'; Body = $bytes; ContentType = 'application/json; charset=utf-8'
                        Headers = @{ 'x-goog-api-key' = $key }; TimeoutSec = [int]$c.TimeoutSec; ErrorAction = 'Stop' }
                if ("$($c.Proxy)".Trim()) { $p.Proxy = "$($c.Proxy)"; $p.ProxyUseDefaultCredentials = $true }
                $r = Invoke-RestMethod @p
                $script:PkgAgent.ModelUsed = $m
                Add-AgentUsage -Usage $r.usageMetadata -Model $m
                Write-AgentAudit -Name $Name -Request $Body -Response $r
                if ($m -ne $Model) { Write-Log "AI: model '$Model' unavailable - used fallback '$m'." Warning }
                return $r
            } catch {
                $status = 0; $detail = "$($_.Exception.Message)"
                try { $resp = $_.Exception.Response; if ($resp) { $status = [int]$resp.StatusCode; $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $t = $sr.ReadToEnd(); $sr.Close(); if ($t) { try { $detail = ($t | ConvertFrom-Json).error.message } catch { $detail = $t } } } } catch {}
                $lastErr = "HTTP $status - $detail"
                $script:PkgAgent.LastError = $lastErr
                if ($status -eq 404 -or ($status -eq 400 -and $detail -match '(?i)not found|not supported|does not exist')) { Write-Log "AI: $m -> $lastErr" Warning; break }   # try the next model
                if ($status -in 401, 403) { Write-AgentAudit -Name $Name -Request $Body -Response $null -Error $lastErr; throw "Gemini rejected the API key ($lastErr)." }
                if ($status -eq 429 -or $status -ge 500 -or $status -eq 0) {
                    $wait = [Math]::Min(30, [int][Math]::Pow(2, $attempt) * 2)
                    Write-Log "AI: $m attempt $attempt failed ($lastErr) - retrying in ${wait}s" Warning
                    Start-Sleep -Seconds $wait; continue
                }
                Write-AgentAudit -Name $Name -Request $Body -Response $null -Error $lastErr
                throw "Gemini request failed: $lastErr"
            }
        }
    }
    Write-AgentAudit -Name $Name -Request $Body -Response $null -Error "$lastErr"
    throw "Gemini request failed after retries: $lastErr"
}

#region OpenAI-compatible gateway (key sk-..., own BaseUrl) -----------------------------------------------------------
# Which provider is in use: explicit setting, else guessed from the key (sk-... = gateway, AIza... = Google).
function Get-AgentProvider {
    $c = Get-AgentConfig
    $p = "$($c.Provider)".Trim().ToLower()
    if ($p -in 'openai', 'openai-compatible', 'gateway') { return 'openai' }
    if ($p -eq 'gemini' -and "$($c.BaseUrl)".Trim() -and "$(Get-AgentApiKey)" -match '^sk-') { return 'openai' }   # settings still say gemini but the key is a gateway key
    return 'gemini'
}
function Get-AgentEndpointText { if ((Get-AgentProvider) -eq 'openai') { "$((Get-AgentConfig).BaseUrl)" } else { $script:AgentEndpoint } }
# Gemini schema (UPPERCASE types) -> JSON schema (lowercase), recursively.
function ConvertTo-OpenAISchema {
    param($S)
    if ($null -eq $S) { return $null }
    if ($S -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $S.Keys) {
            $v = $S[$k]
            if ("$k" -eq 'type' -and $v -is [string]) { $o[$k] = "$v".ToLower() }
            elseif ("$k" -eq 'properties' -and $v -is [System.Collections.IDictionary]) { $pp = [ordered]@{}; foreach ($pk in $v.Keys) { $pp[$pk] = ConvertTo-OpenAISchema $v[$pk] }; $o[$k] = $pp }
            elseif ("$k" -eq 'items') { $o[$k] = ConvertTo-OpenAISchema $v }
            else { $o[$k] = $v }
        }
        return $o
    }
    return $S
}
# Gemini-shaped conversation (contents with parts) -> OpenAI chat messages. Model turns carry tool_calls; each
# functionResponse part becomes a 'tool' message whose tool_call_id is matched by name against the last model turn.
function ConvertTo-OpenAIMessages {
    param([string]$System, [object[]]$Contents)
    $msgs = New-Object System.Collections.Generic.List[object]
    if ($System) { $msgs.Add(@{ role = 'system'; content = "$System" }) }
    $lastIds = @{}   # name -> queue of ids from the most recent assistant turn
    foreach ($c in @($Contents)) {
        $role = "$(if ($c -is [System.Collections.IDictionary]) { $c.role } else { $c.role })"
        $parts = @(if ($c -is [System.Collections.IDictionary]) { $c.parts } else { $c.parts })
        if ($role -eq 'model') {
            $text = ''; $calls = @(); $lastIds = @{}
            foreach ($p in $parts) {
                $ph = if ($p -is [System.Collections.IDictionary]) { $p } else { ConvertTo-AgentHashtable $p }
                if ($ph.Contains('text') -and "$($ph.text)".Trim()) { $text += "$($ph.text)`n" }
                if ($ph.Contains('functionCall') -and $ph.functionCall) {
                    $id = if ("$($ph.id)".Trim()) { "$($ph.id)" } else { 'call_' + [guid]::NewGuid().ToString('N').Substring(0, 12) }
                    $fn = "$($ph.functionCall.name)"
                    $calls += @{ id = $id; type = 'function'; function = @{ name = $fn; arguments = ($(if ($ph.functionCall.args) { $ph.functionCall.args } else { @{} }) | ConvertTo-Json -Depth 30 -Compress) } }
                    if (-not $lastIds.ContainsKey($fn)) { $lastIds[$fn] = New-Object System.Collections.Generic.Queue[string] }; $lastIds[$fn].Enqueue($id)
                }
            }
            $m = @{ role = 'assistant'; content = $(if ($text.Trim()) { $text.Trim() } else { $null }) }
            if ($calls.Count) { $m.tool_calls = @($calls) }
            $msgs.Add($m)
            continue
        }
        # user turn: tool results become 'tool' messages; text/images become one user message with content parts
        $content = @(); $toolMsgs = @()
        foreach ($p in $parts) {
            $ph = if ($p -is [System.Collections.IDictionary]) { $p } else { ConvertTo-AgentHashtable $p }
            if ($ph.Contains('functionResponse') -and $ph.functionResponse) {
                $fn = "$($ph.functionResponse.name)"; $id = ''
                if ($lastIds.ContainsKey($fn) -and $lastIds[$fn].Count) { $id = $lastIds[$fn].Dequeue() }
                $toolMsgs += @{ role = 'tool'; tool_call_id = $id; content = ($ph.functionResponse.response | ConvertTo-Json -Depth 30 -Compress) }
            } elseif ($ph.Contains('inlineData') -and $ph.inlineData) {
                $mime = "$($ph.inlineData.mimeType)"
                if ($mime -match '^image/') { $content += @{ type = 'image_url'; image_url = @{ url = "data:$mime;base64,$($ph.inlineData.data)" } } }
                else { $content += @{ type = 'text'; text = "(a $mime attachment was provided but this gateway mode sends images only)" } }
            } elseif ($ph.Contains('text')) { $content += @{ type = 'text'; text = "$($ph.text)" } }
        }
        foreach ($tm in $toolMsgs) { $msgs.Add($tm) }
        if ($content.Count) { $msgs.Add(@{ role = 'user'; content = @($content) }) }
    }
    return $msgs.ToArray()
}
# OAuth2 client credentials (Keycloak/OIDC token endpoint) -> access token, cached until shortly before expiry.
# The client secret lives ONLY in memory ($script:PkgAgent.ClientSecret) - typed at runtime, never written anywhere.
function Set-AgentAuth {
    param([string]$TokenUrl, [string]$ClientId, [string]$ClientSecret, [string]$Scope, [string]$AuthMode, [string]$ApiKeyHeader)
    if (-not $script:PkgAgent.Overrides) { $script:PkgAgent.Overrides = @{} }
    foreach ($pair in @(@('TokenUrl', $TokenUrl), @('ClientId', $ClientId), @('Scope', $Scope), @('AuthMode', $AuthMode), @('ApiKeyHeader', $ApiKeyHeader))) { if ("$($pair[1])".Trim()) { $script:PkgAgent.Overrides[$pair[0]] = "$($pair[1])".Trim() } }
    if ("$ClientSecret".Trim()) { $script:PkgAgent.ClientSecret = "$ClientSecret".Trim() }
    $script:PkgAgent.AccessToken = $null; $script:PkgAgent.AccessTokenExpires = [datetime]::MinValue
    Write-Log "AI: auth set for this session - tokenUrl=$(if ("$TokenUrl".Trim()) { 'yes' } else { '(none)' }) clientId=$(if ("$ClientId".Trim()) { 'yes' } else { '(none)' }) secret=$(if ($script:PkgAgent.ClientSecret) { 'yes' } else { 'no' }) mode=$(if ("$AuthMode".Trim()) { $AuthMode } else { 'auto' })"
}
function Get-AgentAccessToken {
    param([switch]$Force)
    $c = Get-AgentConfig
    $tu = "$($c.TokenUrl)".Trim(); $cid = "$($c.ClientId)".Trim(); $sec = "$($script:PkgAgent.ClientSecret)"
    if (-not $tu -or -not $cid -or -not $sec) { return $null }
    if (-not $Force -and $script:PkgAgent.AccessToken -and (Get-Date) -lt $script:PkgAgent.AccessTokenExpires) { return $script:PkgAgent.AccessToken }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    try { $dp = [Net.WebRequest]::DefaultWebProxy; if ($dp -and -not $dp.Credentials) { $dp.Credentials = [Net.CredentialCache]::DefaultCredentials } } catch {}
    $form = "grant_type=client_credentials&client_id=$([Uri]::EscapeDataString($cid))&client_secret=$([Uri]::EscapeDataString($sec))"
    if ("$($c.Scope)".Trim()) { $form += "&scope=$([Uri]::EscapeDataString("$($c.Scope)".Trim()))" }
    $p = @{ Uri = $tu; Method = 'Post'; Body = $form; ContentType = 'application/x-www-form-urlencoded'; TimeoutSec = 60; ErrorAction = 'Stop' }
    if ("$($c.Proxy)".Trim()) { $p.Proxy = "$($c.Proxy)"; $p.ProxyUseDefaultCredentials = $true }
    try {
        $r = Invoke-RestMethod @p
        if (-not $r.access_token) { throw 'token endpoint answered without access_token' }
        $ttl = if ($r.expires_in) { [int]$r.expires_in } else { 300 }
        $script:PkgAgent.AccessToken = "$($r.access_token)"; $script:PkgAgent.AccessTokenExpires = (Get-Date).AddSeconds([Math]::Max(30, $ttl - 30))
        Write-Log "AI: access token obtained (expires in ${ttl}s)"
        return $script:PkgAgent.AccessToken
    } catch {
        $detail = "$($_.Exception.Message)"
        try { $resp = $_.Exception.Response; if ($resp) { $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $t = $sr.ReadToEnd(); $sr.Close(); if ($t) { try { $j = $t | ConvertFrom-Json; $detail = "$($j.error): $($j.error_description)" } catch { $detail = $t } } } } catch {}
        throw "Token endpoint refused the client credentials: $detail"
    }
}
# What the access token says about its target: the JWT payload (aud / azp / scope / resource_access / iss) usually
# names the gateway a client is entitled to - the clue when the API base URL was never handed over. Read-only.
function Get-AgentTokenClaims {
    param([string]$Token)
    if (-not $Token) { $Token = Get-AgentAccessToken }
    if (-not $Token) { return $null }
    $parts = $Token.Split('.'); if ($parts.Count -lt 2) { return @{ note = 'opaque token (not a JWT) - no claims to read' } }
    $b64 = $parts[1].Replace('-', '+').Replace('_', '/'); switch ($b64.Length % 4) { 2 { $b64 += '==' } 3 { $b64 += '=' } }
    try { return ((([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))) | ConvertFrom-Json)) } catch { return @{ note = "payload not readable: $($_.Exception.Message)" } }
}
# Plain lines for the verifier: token audience/roles + the realm's discovery document.
function Get-AgentDiscoveryLines {
    $lines = New-Object System.Collections.Generic.List[string]
    $c = Get-AgentConfig
    try {
        $cl = Get-AgentTokenClaims
        if ($cl) {
            foreach ($k in 'iss', 'aud', 'azp', 'scope', 'client_id', 'clientId', 'preferred_username', 'exp') { if ($cl.PSObject.Properties.Name -contains $k) { $v = $cl.$k; if ($v -is [array]) { $v = $v -join ', ' }; if ($k -eq 'exp') { $v = [DateTimeOffset]::FromUnixTimeSeconds([long]$v).LocalDateTime }; $lines.Add("token claim $k = $v") } }
            if ($cl.PSObject.Properties.Name -contains 'resource_access') { foreach ($p in $cl.resource_access.PSObject.Properties) { $lines.Add("token grants access to '$($p.Name)' roles: $(@($p.Value.roles) -join ', ')") } }
            if ($cl.PSObject.Properties.Name -contains 'realm_access') { $lines.Add("realm roles: $(@($cl.realm_access.roles) -join ', ')") }
            if ($cl.PSObject.Properties.Name -contains 'note') { $lines.Add("token: $($cl.note)") }
            $lines.Add('hint: the aud / resource_access names are the services this client may call - the AI gateway URL is documented under that name')
        }
    } catch { $lines.Add("token claims: $($_.Exception.Message)") }
    try {
        $tu = "$($c.TokenUrl)".Trim()
        if ($tu -match '^(.*?/realms/[^/]+)') { $disc = "$($Matches[1])/.well-known/openid-configuration"; $d = Invoke-RestMethod -Uri $disc -TimeoutSec 30 -ErrorAction Stop; $lines.Add("realm: $($d.issuer)  (token endpoint confirmed: $($d.token_endpoint))") }
    } catch { $lines.Add("realm discovery: $($_.Exception.Message)") }
    return $lines.ToArray()
}
# TLS diagnostics: what certificate a host presents and why Windows does not trust it (issuer chain / name / expiry).
function Get-AgentTlsInfo {
    param([Parameter(Mandatory)][string]$HostName, [int]$Port = 443)
    $r = [ordered]@{ Host = $HostName; Ok = $false; Subject = ''; Issuer = ''; Thumbprint = ''; NotAfter = ''; PolicyErrors = ''; Chain = @(); Error = '' }
    $tcp = $null; $ssl = $null
    try {
        $tcp = New-Object Net.Sockets.TcpClient; $tcp.ReceiveTimeout = 8000; $tcp.SendTimeout = 8000
        $ar = $tcp.BeginConnect($HostName, $Port, $null, $null); if (-not $ar.AsyncWaitHandle.WaitOne(8000)) { throw 'TCP connect timeout' }; $tcp.EndConnect($ar)
        $script:__tlsSeen = @{ Errors = ''; Chain = @() }
        $cb = [Net.Security.RemoteCertificateValidationCallback]{ param($s, $cert, $chain, $errors) $script:__tlsSeen.Errors = "$errors"; $script:__tlsSeen.Chain = @($chain.ChainElements | ForEach-Object { "$($_.Certificate.Subject)  <-  $($_.Certificate.Issuer)$(if ($_.ChainElementStatus) { "  [$(($_.ChainElementStatus | ForEach-Object { $_.Status }) -join ',')]" })" }); return $true }
        $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, $cb)
        $ssl.AuthenticateAsClient($HostName, $null, [Security.Authentication.SslProtocols]::Tls12, $false)
        $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
        $r.Subject = $cert.Subject; $r.Issuer = $cert.Issuer; $r.Thumbprint = $cert.Thumbprint; $r.NotAfter = $cert.NotAfter.ToString('yyyy-MM-dd')
        $r.PolicyErrors = $script:__tlsSeen.Errors; $r.Chain = $script:__tlsSeen.Chain; $r.Ok = ($r.PolicyErrors -eq 'None')
    } catch { $r.Error = "$($_.Exception.Message)" }
    finally { try { if ($ssl) { $ssl.Dispose() } } catch {}; try { if ($tcp) { $tcp.Close() } } catch {} }
    return $r
}
function Format-AgentTlsInfo { param($T)
    if ($T.Error -and -not $T.Thumbprint) { return @("tls: $($T.Host) - $($T.Error)") }
    $l = @("tls: $($T.Host) presents '$($T.Subject)' issued by '$($T.Issuer)' (valid to $($T.NotAfter), thumbprint $($T.Thumbprint))")
    if ($T.Ok) { $l += 'tls: certificate is trusted by this machine' } else { $l += "tls: NOT trusted here - $($T.PolicyErrors)"; foreach ($c in $T.Chain) { $l += "     chain: $c" }; $l += "tls: ask IT to install the issuing root CA on this machine, or pin this exact certificate: AI.TrustedThumbprints = [`"$($T.Thumbprint)`"] (agent.settings.json) / Set-AgentTrustedThumbprints" }
    return $l
}
# Pin specific server certificates (thumbprints) for THIS process - never a blanket bypass: anything else keeps Windows' verdict.
$script:AgentTrustedThumbprints = @()
function Set-AgentTrustedThumbprints {
    param([string[]]$Thumbprints)
    $script:AgentTrustedThumbprints = @($Thumbprints | ForEach-Object { "$_".Replace(' ', '').ToUpper() } | Where-Object { $_ })
    if (-not $script:AgentTrustedThumbprints.Count) { return }
    if (-not ('PB.TlsPin' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Net; using System.Net.Security; using System.Security.Cryptography.X509Certificates; using System.Collections.Generic;
namespace PB { public static class TlsPin {
  public static HashSet<string> Pins = new HashSet<string>();
  public static void Install() { ServicePointManager.ServerCertificateValidationCallback += Validate; }
  static bool Validate(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) {
    if (errors == SslPolicyErrors.None) return true;
    if (cert == null) return false;
    string tp = new X509Certificate2(cert).Thumbprint; if (tp == null) return false;
    return Pins.Contains(tp.ToUpperInvariant());
  } } }
'@ -ErrorAction Stop
        [PB.TlsPin]::Install()
    }
    [PB.TlsPin]::Pins.Clear(); foreach ($t in $script:AgentTrustedThumbprints) { [void][PB.TlsPin]::Pins.Add($t) }
    Write-Log "AI: $($script:AgentTrustedThumbprints.Count) server certificate(s) pinned for this session"
}
# Find the gateway when only the identity provider is known: DNS-resolve candidate hosts (derived from the IdP domain and
# the service name in the token, e.g. "llmaas"), then GET /models on the ones that exist. Read-only; reports each answer.
function Find-AgentGatewayCandidates {
    param([string[]]$Extra = @())
    $c = Get-AgentConfig; $lines = New-Object System.Collections.Generic.List[string]; $found = @()
    $idpHost = try { ([Uri]"$($c.TokenUrl)").Host } catch { '' }
    $domains = @(); if ($idpHost) { $parts = $idpHost.Split('.'); for ($i = 1; $i -lt $parts.Count - 1; $i++) { $domains += ($parts[$i..($parts.Count - 1)] -join '.') } }   # cloud.vwgroup.com, vwgroup.com
    $svc = @('llmaas', 'genai', 'ai', 'ai-gateway', 'llm', 'openai', 'gpt', 'gemini')
    try { $cl = Get-AgentTokenClaims; foreach ($k in 'azp', 'client_id') { if ($cl.PSObject.Properties.Name -contains $k) { $v = "$($cl.$k)"; if ($v -match '([a-z][a-z0-9]{2,})-app$') { $svc = @($Matches[1]) + $svc } } } } catch {}
    $hosts = New-Object System.Collections.Generic.List[string]
    foreach ($e in $Extra) { if ("$e".Trim()) { $hosts.Add("$e".Trim()) } }
    foreach ($d in $domains) { foreach ($s in ($svc | Select-Object -Unique)) { foreach ($h in @("$s.$d", "api.$s.$d", "$s-api.$d", "api-$s.$d", "$s.api.$d")) { if (-not $hosts.Contains($h)) { $hosts.Add($h) } } } }
    $lines.Add("probing $($hosts.Count) candidate host names (DNS only; existing ones get one GET /models)")
    foreach ($h in $hosts) {
        $ips = $null; try { $ips = [Net.Dns]::GetHostAddresses($h) } catch {}
        if (-not $ips) { continue }
        $lines.Add("host exists: $h -> $(($ips | Select-Object -First 2 | ForEach-Object { $_.IPAddressToString }) -join ', ')")
        $tls = Get-AgentTlsInfo -HostName $h
        foreach ($l in (Format-AgentTlsInfo $tls)) { $lines.Add("  $l") }
        if (-not $tls.Ok -and $tls.Thumbprint -and ($script:AgentTrustedThumbprints -notcontains $tls.Thumbprint)) { $found += "$h (TLS not trusted - see tls lines)"; continue }   # requests would all fail the same way
        if ($tls.Error -and -not $tls.Thumbprint) { continue }
        $svcPaths = @('/v1', '/api/v1', '/openai/v1') + @($svc | Select-Object -First 3 | ForEach-Object { "/$_/v1"; "/api/$_/v1" }) + @('')
        foreach ($path in $svcPaths) {
            $base = "https://$h$path"
            try {
                $script:PkgAgent.Overrides.BaseUrl = $base
                $ms = @(Get-OpenAIModels)
                $lines.Add("  $base/models -> OK: $(($ms | Select-Object -First 12) -join ', ')"); $found += $base; break
            } catch {
                $st = 0; try { $st = [int]$_.Exception.Response.StatusCode } catch {}
                $lines.Add("  $base/models -> $(if ($st) { "HTTP $st" } else { $_.Exception.Message })$(if ($st -in 401, 403) { '  (exists! auth not accepted with the current mode - try the others)' })")
                if ($st -in 401, 403) { $found += "$base (auth?)" }
            }
        }
    }
    $script:PkgAgent.Overrides.Remove('BaseUrl')
    if (-not $found.Count) { $lines.Add('no candidate answered - ask the LLMaaS / AI platform team for "the OpenAI-compatible base URL" (it may be an internal name not derivable from the IdP domain)') }
    return @{ Lines = $lines.ToArray(); Found = $found }
}
# Headers for the gateway according to AuthMode (auto = token+key when a token is available, else key).
function Get-OpenAIAuthHeaders {
    $c = Get-AgentConfig; $key = "$(Get-AgentApiKey)"
    $mode = "$($c.AuthMode)".Trim().ToLower(); if (-not $mode) { $mode = 'auto' }
    $canToken = [bool]("$($c.TokenUrl)".Trim() -and "$($c.ClientId)".Trim() -and $script:PkgAgent.ClientSecret)
    if ($mode -eq 'auto') { $mode = if ($canToken) { 'token+key' } else { 'key' } }
    $h = @{}
    switch ($mode) {
        'key'       { $h['Authorization'] = "Bearer $key" }
        'token'     { $h['Authorization'] = "Bearer $(Get-AgentAccessToken)" }
        'token+key' { $h['Authorization'] = "Bearer $(Get-AgentAccessToken)"; $hdr = "$($c.ApiKeyHeader)".Trim(); if (-not $hdr) { $hdr = 'x-api-key' }; if ($key) { $h[$hdr] = $key } }
        default     { $h['Authorization'] = "Bearer $key" }
    }
    if ($c.ExtraHeaders) { $eh = if ($c.ExtraHeaders -is [hashtable]) { $c.ExtraHeaders.GetEnumerator() | ForEach-Object { @{ Name = $_.Key; Value = $_.Value } } } else { $c.ExtraHeaders.PSObject.Properties }; foreach ($x in $eh) { $h["$($x.Name)"] = "$($x.Value)" } }
    return $h
}
# POST one chat completion to the gateway. Returns the parsed response. Same retry / error policy as the Google path.
function Invoke-OpenAIRequest {
    param([Parameter(Mandatory)][hashtable]$Body, [Parameter(Mandatory)][string]$Model, [string]$Name = 'call')
    $c = Get-AgentConfig
    $key = Get-AgentApiKey
    if (-not $key -and -not $script:PkgAgent.ClientSecret) { throw 'No API key / client secret. Enter them in the tool (API key) or set GEMINI_API_KEY.' }
    $base = "$($c.BaseUrl)".Trim().TrimEnd('/')
    if (-not $base) { throw "Provider 'openai' needs AI.BaseUrl in agent.settings.json (the gateway URL that came with the sk-... key, e.g. https://gateway.company.com/v1)." }
    $url = if ($base -match '(?i)/chat/completions$') { $base } else { "$base/chat/completions" }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    try { $dp = [Net.WebRequest]::DefaultWebProxy; if ($dp -and -not $dp.Credentials) { $dp.Credentials = [Net.CredentialCache]::DefaultCredentials } } catch {}
    $headers = Get-OpenAIAuthHeaders
    $models = @($Model) + @($c.FallbackModels | Where-Object { $_ -and $_ -ne $Model })
    $lastErr = $null
    foreach ($m in $models) {
        $Body.model = $m
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 40 -Compress))
        for ($attempt = 1; $attempt -le 4; $attempt++) {
            try {
                $p = @{ Uri = $url; Method = 'Post'; Body = $bytes; ContentType = 'application/json; charset=utf-8'; Headers = $headers; TimeoutSec = [int]$c.TimeoutSec; ErrorAction = 'Stop' }
                if ("$($c.Proxy)".Trim()) { $p.Proxy = "$($c.Proxy)"; $p.ProxyUseDefaultCredentials = $true }
                $r = Invoke-RestMethod @p
                $script:PkgAgent.ModelUsed = $m
                $u = $r.usage; if ($u) { Add-AgentUsage -Usage ([pscustomobject]@{ promptTokenCount = [int]$u.prompt_tokens; candidatesTokenCount = [int]$u.completion_tokens; thoughtsTokenCount = 0 }) -Model $m }
                Write-AgentAudit -Name $Name -Request $Body -Response $r
                if ($m -ne $Model) { Write-Log "AI: model '$Model' unavailable - used fallback '$m'." Warning }
                return $r
            } catch {
                $status = 0; $detail = "$($_.Exception.Message)"
                try { $resp = $_.Exception.Response; if ($resp) { $status = [int]$resp.StatusCode; $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $t = $sr.ReadToEnd(); $sr.Close(); if ($t) { try { $j = $t | ConvertFrom-Json; $detail = "$(if ($j.error.message) { $j.error.message } elseif ($j.message) { $j.message } else { $t })" } catch { $detail = $t } } } } catch {}
                $lastErr = "HTTP $status - $detail"
                $script:PkgAgent.LastError = $lastErr
                if ($status -eq 404 -or ($status -in 400, 422 -and $detail -match '(?i)model|not found|does not exist|not supported')) { Write-Log "AI: $m -> $lastErr" Warning; break }
                if ($status -in 401, 403) { Write-AgentAudit -Name $Name -Request $Body -Response $null -Error $lastErr; throw "The gateway rejected the API key ($lastErr)." }
                if ($status -eq 0 -and $attempt -ge 2) { Write-AgentAudit -Name $Name -Request $Body -Response $null -Error $lastErr; throw "Gateway not reachable: $lastErr" }   # no HTTP answer twice = network, stop early
                if ($status -eq 429 -or $status -ge 500 -or $status -eq 0) { $wait = [Math]::Min(30, [int][Math]::Pow(2, $attempt) * 2); Write-Log "AI: $m attempt $attempt failed ($lastErr) - retrying in ${wait}s" Warning; Start-Sleep -Seconds $wait; continue }
                Write-AgentAudit -Name $Name -Request $Body -Response $null -Error $lastErr
                throw "Gateway request failed: $lastErr"
            }
        }
    }
    Write-AgentAudit -Name $Name -Request $Body -Response $null -Error "$lastErr"
    throw "Gateway request failed after retries: $lastErr"
}
# GET <BaseUrl>/models - which model names the gateway serves (for the verifier / error hints).
function Get-OpenAIModels {
    $c = Get-AgentConfig; $key = Get-AgentApiKey
    $base = "$($c.BaseUrl)".Trim().TrimEnd('/'); if (-not $base) { return @() }
    $url = ($base -replace '(?i)/chat/completions$', '') + '/models'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    $headers = Get-OpenAIAuthHeaders
    $p = @{ Uri = $url; Method = 'Get'; Headers = $headers; TimeoutSec = 30; ErrorAction = 'Stop' }
    if ("$($c.Proxy)".Trim()) { $p.Proxy = "$($c.Proxy)"; $p.ProxyUseDefaultCredentials = $true }
    $r = Invoke-RestMethod @p
    return @($r.data | ForEach-Object { "$($_.id)" })
}
#endregion

# One model turn. $Contents = the running conversation (array of @{ role; parts }). Returns
# @{ Content (the model's content object to append verbatim - keeps thought signatures); Text; FunctionCalls=@(@{Name;Args}); Usage; Raw }.
function Invoke-GeminiChat {
    param([string]$System, [Parameter(Mandatory)][object[]]$Contents, [object[]]$Tools, [string]$Model, [hashtable]$ResponseSchema,
          [double]$Temperature = -1, [string]$Name = 'chat', [string]$ToolMode = 'AUTO')
    $c = Get-AgentConfig
    if (-not $Model) { $Model = Get-AgentModel }
    if ($Temperature -lt 0) { $Temperature = [double]$c.Temperature }
    if ((Get-AgentProvider) -eq 'openai' -and -not $script:PkgAgent.Transport) {
        # ---- gateway path: same conversation, OpenAI chat shape ----
        $body = @{ model = $Model; temperature = $Temperature; messages = @(ConvertTo-OpenAIMessages -System $System -Contents $Contents) }
        if ($Tools -and @($Tools).Count) {
            $body.tools = @($Tools | ForEach-Object { $fd = @{ name = $_.name; description = "$($_.description)" }; if ($_.parameters) { $fd.parameters = ConvertTo-OpenAISchema $_.parameters }; @{ type = 'function'; function = $fd } })
            $body.tool_choice = 'auto'
        }
        if ($ResponseSchema) { $body.response_format = @{ type = 'json_object' } }
        $r = Invoke-OpenAIRequest -Body $body -Model $Model -Name $Name
        $msg = $null; try { $msg = @($r.choices)[0].message } catch {}
        if (-not $msg) { throw 'The gateway returned no choice.' }
        $text = "$($msg.content)"
        $parts = @(); $calls = @()
        if ($text.Trim()) { $parts += @{ text = $text } }
        foreach ($tc in @($msg.tool_calls)) {
            if (-not $tc) { continue }
            $args = @{}; try { $raw = "$($tc.function.arguments)"; if ($raw.Trim()) { $args = ConvertTo-AgentHashtable ($raw | ConvertFrom-Json) } } catch { $args = @{ _unparsed = "$($tc.function.arguments)" } }
            $parts += @{ functionCall = @{ name = "$($tc.function.name)"; args = $args }; id = "$($tc.id)" }
            $calls += @{ Name = "$($tc.function.name)"; Args = $args }
        }
        $usage = [pscustomobject]@{ promptTokenCount = [int]$r.usage.prompt_tokens; candidatesTokenCount = [int]$r.usage.completion_tokens }
        return @{ Content = @{ role = 'model'; parts = @($parts) }; Text = $text; FunctionCalls = @($calls); Usage = $usage; Raw = $r; FinishReason = "$(@($r.choices)[0].finish_reason)" }
    }
    $gen = @{ temperature = $Temperature }
    if ($ResponseSchema) { $gen.responseMimeType = 'application/json'; $gen.responseSchema = $ResponseSchema }
    if ($c.Thinking) { $th = @{}; $tp = if ($c.Thinking -is [hashtable]) { $c.Thinking.GetEnumerator() | ForEach-Object { @{ Name=$_.Key; Value=$_.Value } } } else { $c.Thinking.PSObject.Properties }; foreach ($p in $tp) { $th["$($p.Name)"] = $p.Value }; if ($th.Count) { $gen.thinkingConfig = $th } }
    $body = @{ contents = @($Contents); generationConfig = $gen }
    if ($System) { $body.systemInstruction = @{ parts = @(@{ text = "$System" }) } }
    if ($Tools -and @($Tools).Count) {
        $body.tools = @(@{ functionDeclarations = @($Tools) })
        $body.toolConfig = @{ functionCallingConfig = @{ mode = $ToolMode } }
    }
    $r = Invoke-GeminiRequest -Body $body -Model $Model -Name $Name
    $cand = $null; try { $cand = @($r.candidates)[0] } catch {}
    if (-not $cand) {
        $reason = try { "$($r.promptFeedback.blockReason)" } catch { '' }
        throw "Gemini returned no candidate$(if ($reason) { " (blocked: $reason)" })."
    }
    $parts = @(); try { $parts = @($cand.content.parts) } catch {}
    $text = (@($parts | Where-Object { $_.PSObject.Properties.Name -contains 'text' } | ForEach-Object { "$($_.text)" }) -join "`n")
    $calls = @()
    foreach ($p in $parts) {
        if ($p.PSObject.Properties.Name -contains 'functionCall' -and $p.functionCall) {
            $calls += @{ Name = "$($p.functionCall.name)"; Args = (ConvertTo-AgentHashtable $p.functionCall.args) }
        }
    }
    return @{ Content = $cand.content; Text = $text; FunctionCalls = @($calls); Usage = $r.usageMetadata; Raw = $r; FinishReason = "$($cand.finishReason)" }
}
# PSCustomObject (from JSON) -> nested hashtable/arrays, so agent code can index freely.
function ConvertTo-AgentHashtable {
    param($Obj)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}; foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-AgentHashtable $p.Value }; return $h
    }
    if ($Obj -is [array] -or ($Obj -is [System.Collections.IList] -and $Obj -isnot [string])) { return ,@(foreach ($i in $Obj) { ConvertTo-AgentHashtable $i }) }
    return $Obj
}
# A quick connectivity/key check: tiny prompt, returns @{ Ok; Model; Error; Steps=@(lines) }. The Steps explain WHERE it
# fails (name resolution -> proxy -> TLS -> key -> model), so "works from this network?" gets a plain answer.
function Test-GeminiConnection {
    $steps = New-Object System.Collections.Generic.List[string]
    $prov = Get-AgentProvider; $c = Get-AgentConfig
    $url = if ($prov -eq 'openai') { "$($c.BaseUrl)".Trim() } else { $script:AgentEndpoint }
    $steps.Add("provider: $prov   model: $(Get-AgentModel)   endpoint: $(if ($url) { $url } else { '(none)' })   key: $(if (Test-AgentHasKey) { "$($script:PkgAgent.KeySource), $("$(Get-AgentApiKey)".Substring(0, [Math]::Min(6, "$(Get-AgentApiKey)".Length)))..." } else { 'none' })")
    $canTokenEarly = [bool]("$($c.TokenUrl)".Trim() -and "$($c.ClientId)".Trim() -and $script:PkgAgent.ClientSecret)
    if ($prov -eq 'openai' -and -not $url) {
        if ($canTokenEarly) {
            # no API URL yet, but credentials: at least prove the identity provider accepts them and show what the token is FOR
            try { $null = Get-AgentAccessToken -Force; $steps.Add("token: OK - the identity provider accepted client id + secret"); foreach ($l in (Get-AgentDiscoveryLines)) { $steps.Add($l) } }
            catch { $steps.Add("token: FAILED - $($_.Exception.Message)") }
            try { $pr = Find-AgentGatewayCandidates; foreach ($l in $pr.Lines) { $steps.Add($l) }; if ($pr.Found.Count) { $steps.Add("CANDIDATE ENDPOINT(S): $($pr.Found -join ' | ')  - enter one as the endpoint URL and test again") } } catch { $steps.Add("probe: $($_.Exception.Message)") }
            $steps.Add('next: enter the AI gateway API base URL (…/v1) as endpoint - the token endpoint cannot serve chat')
            return @{ Ok = $false; Model = ''; Error = 'No endpoint URL yet (token check only).'; Steps = $steps }
        }
        return @{ Ok = $false; Model = ''; Error = 'No endpoint URL - a sk-... key belongs to a gateway; enter its base URL.'; Steps = $steps }
    }
    if ($prov -eq 'openai' -and $url -match '(?i)openid-connect/token|/oauth2?/token|/realms/') {
        $steps.Add('STOP: this endpoint URL is an identity-provider TOKEN endpoint (…/openid-connect/token). It only issues access tokens - it has no /chat/completions, so it answers 404/405.')
        $steps.Add('Put it into "Token URL" (with client id + secret) and enter the AI gateway''s API base URL (usually ending in /v1) as the endpoint.')
        return @{ Ok = $false; Model = ''; Error = 'Endpoint URL is a token endpoint, not the AI API.'; Steps = $steps }
    }
    if ("$(Get-AgentApiKey)" -match '^AIza' -and $prov -eq 'openai') { $steps.Add('note: the key looks like a Google key (AIza...) but a gateway URL is set') }
    if ("$(Get-AgentApiKey)" -match '^sk-' -and $prov -eq 'gemini') { $steps.Add('note: sk-... is NOT a Google Gemini key - it needs the gateway URL it came with') }
    try {
        $uri = [Uri]$url
        try { $ips = [Net.Dns]::GetHostAddresses($uri.Host); $steps.Add("dns: $($uri.Host) -> $(($ips | Select-Object -First 3 | ForEach-Object { $_.IPAddressToString }) -join ', ')") } catch { $steps.Add("dns: $($uri.Host) NOT resolvable from this machine ($($_.Exception.Message)) - network/allow-list issue, not the key") }
        try { $px = [Net.WebRequest]::DefaultWebProxy; $pu = if ($px) { $px.GetProxy($uri) } else { $null }; $steps.Add("proxy: $(if ($pu -and $pu.AbsoluteUri -ne $uri.AbsoluteUri) { $pu.AbsoluteUri } else { 'direct' })$(if ("$($c.Proxy)".Trim()) { " (settings: $($c.Proxy))" })") } catch {}
    } catch {}
    # Gateway behind an identity provider: get the access token first (its own clear error), then, in AuthMode 'auto',
    # try the header combinations gateways use until one answers - and keep the working one for the session.
    $modes = @($null)
    if ($prov -eq 'openai') {
        $canToken = [bool]("$($c.TokenUrl)".Trim() -and "$($c.ClientId)".Trim() -and $script:PkgAgent.ClientSecret)
        if ($canToken) {
            try { $null = Get-AgentAccessToken -Force; $steps.Add("token: OK - access token from $(([Uri]"$($c.TokenUrl)").Host) (expires $($script:PkgAgent.AccessTokenExpires.ToString('HH:mm:ss')))"); foreach ($l in (Get-AgentDiscoveryLines)) { $steps.Add($l) } }
            catch { $steps.Add("token: FAILED - $($_.Exception.Message)"); $steps.Add('meaning: the identity provider rejected client id / secret (or the token URL is wrong) - the AI service was not reached yet'); return @{ Ok = $false; Model = ''; Error = "$($_.Exception.Message)"; Steps = $steps } }
            if ("$($c.AuthMode)".Trim().ToLower() -in '', 'auto') { $modes = @(@{ AuthMode = 'token+key'; ApiKeyHeader = 'x-api-key' }, @{ AuthMode = 'token+key'; ApiKeyHeader = 'api-key' }, @{ AuthMode = 'token' }, @{ AuthMode = 'key' }) }
        }
    }
    $err = ''
    foreach ($mode in $modes) {
        if ($mode) { Set-AgentAuth -AuthMode $mode.AuthMode -ApiKeyHeader $mode.ApiKeyHeader; $steps.Add("trying auth: $($mode.AuthMode)$(if ($mode.ApiKeyHeader) { " (key header $($mode.ApiKeyHeader))" })") }
        try {
            $r = Invoke-GeminiChat -Contents @(@{ role = 'user'; parts = @(@{ text = 'Reply with the single word OK.' }) }) -Name 'connection-test' -Temperature 0
            $steps.Add("chat: OK - '$($r.Text.Trim())' from $($script:PkgAgent.ModelUsed)$(if ($mode) { "   [auth mode kept for this session: $($mode.AuthMode)$(if ($mode.ApiKeyHeader) { " / $($mode.ApiKeyHeader)" })]" })")
            return @{ Ok = $true; Model = $script:PkgAgent.ModelUsed; Error = ''; Text = $r.Text; Steps = $steps }
        } catch {
            $err = "$($_.Exception.Message)"
            $steps.Add("chat: FAILED - $err")
            if ($mode -and $err -notmatch 'HTTP 401|HTTP 403') { break }   # only an auth rejection justifies trying the next combination
        }
    }
    if ($err -match '(?i)trust relationship|SSL/TLS|secure channel') { try { $tls = Get-AgentTlsInfo -HostName ([Uri]$url).Host; foreach ($l in (Format-AgentTlsInfo $tls)) { $steps.Add($l) } } catch {}; $steps.Add('meaning: HTTPS certificate of the gateway is not trusted on this machine (the key was never checked) - root CA missing here, or pin the thumbprint above') }
    elseif ($err -match 'HTTP 0 ') { $steps.Add('meaning: no HTTP answer at all - proxy / firewall / TLS on this network (the key was never checked)') }
        elseif ($err -match 'HTTP 401|HTTP 403') { $steps.Add('meaning: the gateway answered and REJECTED the key (wrong key, expired, or not licensed for this tenant/brand)') }
        elseif ($err -match 'HTTP 400|HTTP 404|HTTP 422') { $steps.Add('meaning: reached the service; the request/model name is not accepted there') }
        elseif ($err -match 'HTTP 407') { $steps.Add('meaning: the corporate proxy wants authentication - set AI.Proxy or ask the network team to allow this host') }
        elseif ($err -match 'HTTP 502|HTTP 503|HTTP 504') { $steps.Add('meaning: the answer came from the proxy/network, not the AI service - the host is not reachable/allowed from this network (ask the network team to allow it), or the service is down') }
    if ($prov -eq 'openai') { try { $ms = @(Get-OpenAIModels); if ($ms.Count) { $steps.Add("models the gateway lists: $(($ms | Select-Object -First 25) -join ', ')") } } catch { $steps.Add("models list: $($_.Exception.Message)") } }
    return @{ Ok = $false; Model = $script:PkgAgent.ModelUsed; Error = $err; Steps = $steps }
}
#endregion
