---
name: select-workspace
description: Pick a PMCollab workspace for a downstream workflow. Use when another PMCollab skill delegates with "select a PMCollab workspace," when the user says "pick a workspace" / "switch PMCollab workspaces," or when a workflow needs workspaceId. Returns workspaceId + workspaceTitle. Identity (userId / email / displayName / tenantId) is auto-resolved by the pmc-mcp server from the authenticated connection — do NOT prompt the user for it. Use-case selection is a separate skill (select-usecase) — do NOT pick use cases here.
---

# select-workspace

Resolve a PMCollab workspace via the `pmc-mcp` MCP server, prompting the user once for identity and caching it. This is a building-block skill — workflow skills (e.g. `chat-to-spec-review`) invoke it instead of duplicating workspace-picker logic.

Use-case selection is intentionally **out of scope** for this skill — it lives in the companion `select-usecase` skill, which expects a `workspaceId` that this skill has already resolved.

## When to invoke

- Another PMCollab skill explicitly delegates to `select-workspace`.
- The user says "pick a PMCollab workspace," "switch workspaces," or "use a different workspace for this."
- A workflow needs `workspaceId` but doesn't yet have it.

If a workspace was chosen earlier in the session and the user hasn't signalled a change, reuse the cached value instead of re-invoking this skill.

## Hard rules

- **Never invent IDs.** Every ID comes from an MCP tool response.
- **Do NOT prompt for identity.** The `pmc-mcp` server resolves the caller's `userId`, `email`, `tenantId`, and `displayName` from the authenticated connection automatically. Every identity-bearing tool (`workspace_list`, `usecase_create`, `spec_document_create`, `capability_create`, `spec_review_start`, `spec_readiness_review`, `spec_readiness_eval`, …) defaults these args from that context. If you ever find yourself about to ask the user for `userId`, stop — the connection already has it.
- **Surface workspace maturity in the picker.** It helps the caller anticipate downstream gates (e.g. Spec Review's minimum maturity).
- **Do not list use cases here.** Hand off to `select-usecase` once `workspaceId` is resolved if the caller needs one.

## Step 1 — List workspaces

Call `workspace_list` with NO arguments — identity is auto-resolved from the PAT. Render the response as a numbered list, including the workspace's current maturity stage in parentheses:

```
1. Acme PMC Workspace (shaping)
2. Beta Pilot (spark)
```

Wait for the user to pick a number or workspace title. Capture `workspaceId` and `workspaceTitle`.

## Step 2 — Return the resolved identifiers

Report the resolved values back in chat so the calling skill (and the user) can see them:

> "Resolved: workspace **Acme PMC Workspace** (`<workspaceId>`)."

The calling skill consumes:

- `workspaceId` — required for every downstream tool that takes one
- `workspaceTitle` — for human-readable confirmation prompts

Downstream tools do NOT need an identity payload from this skill — every server-side tool defaults `createdBy` / `evaluatedBy` / `createdByName` from the PAT context automatically. Callers may still pass these args explicitly to override the PAT-resolved values (useful for standalone tests), but no human prompting is required.

If the caller also needs a use case, it should now invoke `select-usecase` and pass the resolved `workspaceId`.

## Out of scope

- Listing or selecting use cases — that's `select-usecase`.
- Creating workspaces — this skill only selects existing ones.
- Editing workspace metadata, maturity, or membership.
- Calling any workflow tool beyond `workspace_list`.
