---
description: Load a per-file extracted-facts pack (business rules + AI prompts + MCP/A2A endpoints + change-log) for code backing one PMCollab use case.
---

# /pm:load-code-context

Hydrate Claude with the code-side context for a use case in one round trip. Calls the MCP tool `code_load_context` with `{workspaceId, useCaseId}` and returns its pack as-is — no synthesis, no rephrasing.

## Required inputs

- `workspaceId` — the workspace (same value as productContextId).
- `useCaseId` — the use case to load.

If either is missing, run `/pm:select-usecase` first (which auto-chains to `/pm:select-workspace`).

## Hard rules

- **One MCP call.** Make exactly one `code_load_context` call per invocation — do not pad with discovery calls.
- **Pass the pack through.** Do not summarize or paraphrase the JSON returned by the tool. Calling workflows consume the structured pack directly.
- **Handle null `scan` cleanly.** When `scan === null` the workspace has no completed scan yet — surface that fact to the user and stop. Do not fabricate file paths or rules.
- **Read-only.** This command does not edit files, the spec, or any PMCollab record.
- **Pack contains extracted facts, not file bytes.** If the calling workflow needs to compare against the live source, it should `Read` the files at the paths listed in `files[].path` from the local working directory.

## Step 1 — Validate inputs

Confirm both `workspaceId` and `useCaseId` are present. If not, delegate to `/pm:select-usecase`.

## Step 2 — Call the MCP tool

Invoke `code_load_context` with exactly:

```json
{ "workspaceId": "<workspaceId>", "useCaseId": "<useCaseId>" }
```

Parse the JSON-stringified text block returned in `content[0].text`.

## Step 3 — Hand the pack to the caller

Return the parsed pack to the calling workflow. Surface a short human-readable confirmation in chat:

> "Loaded code context for **<useCase title>**: scan `<scan.type>` from `<scan.scannedAt>` (`<scan.repoIdentifier>`) · <files.length> files · <businessRules.length> business rules · <aiPrompts.length> AI prompts · <changeLog.length> change-log entries scoped to this use case."

When `scan === null`:

> "No completed code scan found for this workspace. Run a code scan in PMCollab first, then retry."

## Out of scope

- Rendering / diffing the extracted artifacts — leave that to the calling workflow.
- Reading the live local files — the calling workflow does that with its own `Read` tool.
- Filtering / trimming the pack — the server has already scoped to the use case.
- Editing anything (files, spec, capabilities, behaviors).
