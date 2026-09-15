---
name: ado-pipeline-idea-dropped
description: "Azure DevOps pipeline + Citrix→Azure migration for the packaging workflow was evaluated Sept 2026 and dropped by the user — don't re-propose"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f1cafd55-2e38-401d-a3f1-eeb2766a2dd3
  modified: 2026-09-14T07:21:30.657Z
---

On 2026-09-14 the user asked whether the packaging workflow could run as an Azure DevOps pipeline (replacing Citrix VDI sessions with ephemeral agents, approval gates, SP-auth deploy). After a full proposal (stage map, cost/break-even, 17-week plan) they judged it "not much useful compared to the complete environment we are going to implement" and told me to leave the idea.

**Why:** the team has a different complete-environment plan in progress; the ADO approach was seen as low value relative to it.

**How to apply:** don't re-propose ADO pipelines / CI-style automation / Citrix replacement for Package Builder unless the user raises it. If they do, the proposal artifact still exists (Packaging Pipeline on Azure DevOps, https://claude.ai/code/artifact/340e8600-27c0-43e4-8c8e-b218f80920ee). Related: [[automation-scope-not-useful]], [[pb-agent-story]].
