---
description: Pick a PMCollab workspace and resolve its workspaceId for the session.
---

# /pm:select-workspace

Resolve a PMCollab workspace via the `pmc-mcp` MCP server. Identity (`userId` / `email` / `tenantId` / `displayName`) is auto-resolved from the authenticated connection — do NOT prompt the user for it.

Use-case selection is intentionally **out of scope** here — it lives in the companion `/pm:select-usecase` command, which expects a `workspaceId` that this command has already resolved.

## Hard rules

- **Never invent IDs.** Every ID comes from an MCP tool response.
- **Do NOT prompt for identity.** The `pmc-mcp` server resolves the caller's `userId`, `email`, `tenantId`, and `displayName` from the authenticated connection automatically. Every identity-bearing tool (`workspace_list`, `usecase_create`, `spec_document_create`, `capability_create`, `spec_review_start`, `spec_readiness_review`, `spec_readiness_eval`, …) defaults these args from that context. If you ever find yourself about to ask the user for `userId`, stop — the connection already has it.
- **Surface workspace maturity in the picker.** It helps the caller anticipate downstream gates (e.g. Spec Review's minimum maturity).
- **Do not list use cases here.** Hand off to `/pm:select-usecase` once `workspaceId` is resolved if the caller needs one.

## Step 1 — List workspaces

Call `workspace_list` with NO arguments — identity is auto-resolved from the PAT. Render the response as a numbered list, including the workspace's current maturity stage in parentheses:

```
1. Acme PMC Workspace (shaping)
2. Beta Pilot (spark)
```

Wait for the user to pick a number or workspace title. Capture `workspaceId` and `workspaceTitle`.

## Step 2 — Return the resolved identifiers

Report the resolved values back in chat so the user (and any follow-up workflow) can see them:

> "Resolved: workspace **Acme PMC Workspace** (`<workspaceId>`)."

Downstream tools do NOT need an identity payload from this command — every server-side tool defaults `createdBy` / `evaluatedBy` / `createdByName` from the PAT context automatically. Callers may still pass these args explicitly to override the PAT-resolved values (useful for standalone tests), but no human prompting is required.

If the caller also needs a use case, suggest `/pm:select-usecase` and pass the resolved `workspaceId`.

## Out of scope

- Listing or selecting use cases — that's `/pm:select-usecase`.
- Creating workspaces — this command only selects existing ones.
- Editing workspace metadata, maturity, or membership.
- Calling any workflow tool beyond `workspace_list`.
