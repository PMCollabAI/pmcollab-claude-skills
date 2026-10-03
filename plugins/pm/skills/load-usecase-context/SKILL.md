---
name: load-usecase-context
description: Load a tight LLM-context pack for a selected PMCollab use case via one MCP call (usecase_load_context). Use after select-usecase has resolved {workspaceId, useCaseId}, when another PMCollab skill says "load context for this use case," or when the user says "pull down the use case context" / "load the spec for the selected use case." Returns one JSON object containing the use case essentials (title, description, status, detail bullets grouped by field, linked personas), every capability under it with its non-rejected behaviors compacted to {group, content}, and the CurrentSpec markdown (baseline creation spec + applied change specs collapsed) with its lineage and the baselineSpecDocumentId a change spec is authored against. currentSpec is null when not yet promoted.
---

# load-usecase-context

Hydrate the agent's working memory for one use case in one round trip. Calls the MCP tool `usecase_load_context` with `{workspaceId, useCaseId}` and returns its pack as-is — no synthesis, no rephrasing.

## When to invoke

- A calling skill says "load context for this use case" after `select-usecase` has resolved a `useCaseId`.
- The user says "pull down the use case context," "load the spec," "get me everything for this use case," or similar.
- A workflow skill needs the use case essentials + capability behaviors + CurrentSpec to proceed.

If a fresh pack was already loaded earlier in the same session and the use case hasn't changed, reuse the cached pack instead of re-invoking — the data is read-only and won't have shifted within seconds.

## Required inputs

- `workspaceId` — the workspace (same value as productContextId).
- `useCaseId` — the use case to load.

If either is missing, invoke `select-usecase` first (which auto-chains to `select-workspace`). Do not call `usecase_load_context` with placeholder IDs.

## Hard rules

- **One MCP call.** Make exactly one `usecase_load_context` call per invocation — do not pad with `workspace_list_usecases`, `spec_document_list`, or other discovery calls. The whole point is one tight round trip.
- **Pass the pack through.** Do not summarize, reword, or reformat the JSON returned by the tool. The calling skill consumes the structured pack directly; lossy paraphrasing defeats the purpose.
- **Handle null `currentSpec` cleanly.** When `currentSpec === null` the use case has not been promoted yet (or has no spec markdown). Surface that fact to the user — don't fabricate a spec.
- **`currentSpec.baselineSpecDocumentId` is the baseline a change spec is authored against**, on both `source` values — `creation-spec` just means no change spec has been applied yet, which is the normal state of a freshly promoted use case. Null means no promoted design spec backs the record, and the caller resolves one with `spec_document_list_by_usecase`. `baseCreationSpecId` is lineage only: it is a CreationSpec id in a different id space and is never a `baselineSpecDocumentId`.
- **Don't edit anything.** This skill is read-only.

## Step 1 — Validate inputs

Confirm you have both `workspaceId` and `useCaseId`. If not, delegate to `select-usecase`.

## Step 2 — Call the MCP tool

Invoke `usecase_load_context` with exactly:

```json
{ "workspaceId": "<workspaceId>", "useCaseId": "<useCaseId>" }
```

The tool returns one text block whose body is a JSON-stringified pack. Parse it.

## Step 3 — Hand the pack to the caller

Return the parsed pack object to the calling skill. Also surface a short human-readable confirmation in chat so the user sees what was loaded:

> "Loaded context for **<useCase.title>**: <N capabilities> · <M behaviors total> · CurrentSpec source = <currentSpec.source ?? 'none'>."

When `currentSpec === null`, say so explicitly:

> "Loaded context for **<useCase.title>**: <N capabilities> · <M behaviors total> · no promoted spec yet."

## Out of scope

- Rendering / formatting the spec markdown — leave that to the calling workflow.
- Editing the use case, capabilities, behaviors, or spec.
- Loading multiple use cases in one call — invoke once per use case.
- Filtering or trimming the pack — the server already excludes rejected behaviors and empty detail-bullet groups.
