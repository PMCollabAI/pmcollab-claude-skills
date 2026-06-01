---
description: Load a tight LLM-context pack (essentials + capabilities + CurrentSpec) for one PMCollab use case via one MCP call.
---

# /pm:load-usecase-context

Hydrate Claude's working memory for one use case in one round trip. Calls the MCP tool `usecase_load_context` with `{workspaceId, useCaseId}` and returns its pack as-is — no synthesis, no rephrasing.

## Required inputs

- `workspaceId` — the workspace (same value as productContextId).
- `useCaseId` — the use case to load.

If either is missing, run `/pm:select-usecase` first (which auto-chains to `/pm:select-workspace`). Do not call `usecase_load_context` with placeholder IDs.

## Hard rules

- **One MCP call.** Make exactly one `usecase_load_context` call per invocation — do not pad with `workspace_list_usecases`, `spec_document_list`, or other discovery calls. The whole point is one tight round trip.
- **Pass the pack through.** Do not summarize, reword, or reformat the JSON returned by the tool. The calling workflow consumes the structured pack directly; lossy paraphrasing defeats the purpose.
- **Handle null `currentSpec` cleanly.** When `currentSpec === null` the use case has not been promoted yet (or has no spec markdown). Surface that fact to the user — don't fabricate a spec.
- **Don't edit anything.** This command is read-only.

## Step 1 — Validate inputs

Confirm you have both `workspaceId` and `useCaseId`. If not, delegate to `/pm:select-usecase`.

## Step 2 — Call the MCP tool

Invoke `usecase_load_context` with exactly:

```json
{ "workspaceId": "<workspaceId>", "useCaseId": "<useCaseId>" }
```

The tool returns one text block whose body is a JSON-stringified pack. Parse it.

## Step 3 — Hand the pack to the caller

Return the parsed pack object to the calling workflow. Also surface a short human-readable confirmation in chat so the user sees what was loaded:

> "Loaded context for **<useCase.title>**: <N capabilities> · <M behaviors total> · CurrentSpec source = <currentSpec.source ?? 'none'>."

When `currentSpec === null`, say so explicitly:

> "Loaded context for **<useCase.title>**: <N capabilities> · <M behaviors total> · no promoted spec yet."

## Out of scope

- Rendering / formatting the spec markdown — leave that to the calling workflow.
- Editing the use case, capabilities, behaviors, or spec.
- Loading multiple use cases in one call — invoke once per use case.
- Filtering or trimming the pack — the server already excludes rejected behaviors and empty detail-bullet groups.
