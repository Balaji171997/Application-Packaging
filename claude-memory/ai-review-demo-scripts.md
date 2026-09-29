---
name: ai-review-demo-scripts
description: "PackagingAgent\\Demo (2 scripts made to show the VW AI team how we call the API) was DELETED 28 Sep 2026 at the user's request; recreate minimal scripts outside the agent only if asked again"
metadata:
  node_type: memory
  type: project
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-28T12:42:36.482Z
---

24 Sep 2026 the VW AI team asked to see how we call the LLMaaS API, so two tiny readable scripts were built in
`PackagingAgent\Demo\` (connect + read-an-order). On 28 Sep 2026 the user asked to remove the Demo folder and keep
only what the agent needs — it is gone (it was never committed to git).

**Why:** the user wants the agent folder to hold only relevant content.

**How to apply:** if a "show the AI team how we connect" request comes back, write fresh minimal scripts outside
the agent folder (the proven auth is in [[vw-llmaas-connection]] and `Src\Agent.Gemini.ps1`); do not re-add Demo\
to the agent. Related: [[ai-agent-integration-plan]].
