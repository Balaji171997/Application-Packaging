---
name: vw-llmaas-connection
description: "The WORKING VW LLMaaS connection settings (base URL, token endpoint, two auth headers incl. the \"Bearer \" prefix on the API key) - proven 25 Sep 2026 after a long 401 hunt"
metadata:
  node_type: memory
  type: reference
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-25T04:08:23.788Z
---

VW Group **LLMaaS** (LLM as a Service) — the configuration that actually works from the MAN network:

```
BaseUrl      https://llmapi.ai.vwgroup.com/v1      (the sample from the AI team uses no /v1 and appends /chat/completions; with /v1 it works too)
TokenUrl     https://idp.cloud.vwgroup.com/auth/realms/kums-mfa/protocol/openid-connect/token
ClientId     idp-<guid>-llmaas-app                 (client_credentials grant; client secret is a secret)
Model        gemini-2.5-flash-lite                 (their sample defaults to gpt-5.1 — several models are served)
```

**Both credentials travel, in TWO headers, and the key header ALSO carries the word Bearer:**
```
Authorization:        Bearer <access token from the IdP>
X-LLM-API-CLIENT-ID:  Bearer <API key sk-...>
```
Anything else = HTTP 401: key alone, token alone, key in `api-key`/`x-api-key`, or the bare key without the `Bearer ` prefix (all six combinations were tested and all returned 401). This cost days; the answer came from the AI team's own sample script.

Implemented in `PackagingAgent\Src\Agent.Gemini.ps1`: config keys `ApiKeyHeader` + **`ApiKeyPrefix`** (default `'Bearer '`), used by `Get-OpenAIAuthHeaders`; `Set-AgentAuth -ApiKeyPrefix/-NoPrefix`; the auto-probe tries the LLMaaS combination first. The review copy `PackagingAgent\Demo\1-Connect-Ai.ps1` was corrected on 25 Sep (it still sent the bare key in `api-key`). Regression tests in `PackagingAgent\Tests\Test-Agent.ps1`: "llmaas: key header + Bearer prefix" for the client, plus "demo: …" assertions so the teaching copy cannot drift again.

**PS 5.1 trap found here:** `Get-AgentConfig` skipped overrides whose value was an empty string, so a deliberate `ApiKeyPrefix = ''` fell back to the default — override checks must be `$null -ne $value`, not truthiness.

**25 Sep — "connection test passes but intake gives 401":** THE CLIENT SECRET IS AS REQUIRED AS THE KEY, and it was only ever held in memory. Three compounding causes, all fixed: (1) intake/evaluation run in a **background runspace** that re-loads the agent from disk, and `Start-AgentRunspace`'s payload carried only the API key — not the secret, not the auth overrides; (2) `Get-AgentApiKey`/the secret were never read from `agent.settings.json` (the old rule was "the secret is never in a file", which the user had since overruled); (3) `Get-AgentAccessToken` **returned `$null`** when the secret was missing, so the request went out with an empty `Authorization: Bearer ` and the gateway's 401 blamed the API key. Now: `Get-AgentClientSecret` (memory → file) is the single source, the payload carries secret + overrides, and `Assert-AgentAccessToken` throws naming the missing piece. Four regression tests in `Tests\Test-Agent.ps1` ("settings file: …", "auto mode uses token+key from the file", "missing secret names the secret, not the key", "runspace payload carries secret + overrides").

**25 Sep — LLMaaS answers HTTP 200 with `choices: []`:** on the post-snapshot `classify` call (one ~35 KB user message + the `submit_decision` tool schema, 9,224 prompt tokens) `gemini-2.5-flash-lite` returned **no candidate at all** — empty choices, `completion_tokens: 0`, empty safety/grounding arrays. Extract and decide had worked minutes earlier, so it is not auth and not the payload size alone; the tool-call path is the suspect. An empty candidate used to arrive as a *success*, so no retry or fallback applied and the stage died with "The gateway returned no choice." Now `Invoke-OpenAIRequest` treats it as a failure (retry ×3 → `FallbackModels` → ...) and `Invoke-GeminiChat` finally re-asks **without tools** using `response_format json_object`, converting the JSON back into the function call (`FinishReason: json-fallback`). Proven end to end by `Tests\Test-Gateway.ps1`, a raw-TCP stand-in gateway that replays the exact response (it must answer `Expect: 100-continue`, or .NET never sends the body).

**How to apply:** for any new AI endpoint, first ask which header carries the key and whether its value needs a prefix; the 401 says nothing. When a stage fails, read `WorkRoot\AI\<package>\NNN-<task>.json` first — the recorded response usually names the problem outright. Related: [[ai-agent-integration-plan]], [[ai-review-demo-scripts]].
