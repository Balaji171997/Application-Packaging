---
name: ai-agent-integration-plan
description: "Packaging Agent = STANDALONE app in repo\\PackagingAgent (Src/Engine/Knowledge/Template/Tests/Tools/Docs + Run-PackagingAgent.cmd); never integrated into Package Assistance; flow intake→plan→prepare→evaluate→build→verify→handover; our template only; key/secret per session, never written anywhere"
metadata:
  node_type: memory
  type: project
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-28T12:42:56.731Z
---

Standing rules for the Packaging Agent (Sept 2026, still binding):

- **Separate product** in `Application-Packaging\PackagingAgent\`, one self-contained folder (copy it anywhere and it
  runs). NEVER put agent code or buttons into any Package Assistance folder — an early attempt was reverted at the
  user's demand. `Engine\` is the agent's own library now (no sync).
- **Our template only; the tool builds, the AI judges.** The package is built by the hands from the team's PSADT
  template (`Template\`), from the predecessor's script on a reuse; the AI's changes go in as exact edits, never a
  rewrite of the template.
- **Secrets**: the API key and client secret live only in the git-ignored `agent.settings.json` (the user enters
  them) or the session; never print, copy or write them anywhere else.
- **Machine**: the Citrix VDI / the user's workstation is the evaluation machine; network shares and the
  predecessor package are read-only to the AI, local disk is its workshop; the AI is told to be careful with the
  system rather than being fenced off from it.
- **Testing**: the user runs live tests; do not run live models for installs/troubleshooting unless asked.
- Folder holds only what the agent needs (user, 28 Sep 2026) — the Demo folder was removed.

Current design and history: [[packaging-agent-process-record]] (read first) and [[packaging-agent-architecture]];
connection details in [[vw-llmaas-connection]].
