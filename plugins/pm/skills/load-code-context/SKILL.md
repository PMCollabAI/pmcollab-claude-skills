---
name: load-code-context
description: Load a tight per-file extracted-facts pack for the code that backs a selected PMCollab use case via one MCP call (code_load_context). Use after select-usecase has resolved {workspaceId, useCaseId}, when another PMCollab skill says "load code context for this use case," or when the user says "pull down the code snapshot" / "load the related files." Returns one JSON object containing scan provenance (id, type, scannedAt, repoIdentifier), the matched extracted capability names, a per-file index of which business rules / AI prompts / MCP / A2A endpoints / change-log entries reference each file, and the full extracted artifacts scoped to the use case. scan is null when no completed scan exists. Returns extracted facts, NOT raw file bytes — calling skills should also Read the live local files for byte-level comparison.
---

# load-code-context

Hydrate Claude with the code-side context for a use case in one round trip. Calls the MCP tool `code_load_context` with `{workspaceId, useCaseId}` and returns its pack as-is — no synthesis, no rephrasing.

## When to invoke

- A calling skill says "load code context for this use case" after `select-usecase` has resolved a `useCaseId`.
- The user says "pull down the code snapshot," "load the related files," or "show me what code touches this use case."
- A workflow skill (e.g. `spec-align`) needs the per-file extracted facts to reason about drift.

If a fresh pack was already loaded earlier in the same session and the use case + scan haven't changed, reuse the cached pack instead of re-invoking.

## Required inputs

- `workspaceId` — the workspace (same value as productContextId).
- `useCaseId` — the use case to load.

If either is missing, invoke `select-usecase` first (which auto-chains to `select-workspace`).

## Hard rules

- **One MCP call.** Make exactly one `code_load_context` call per invocation — do not pad with discovery calls.
- **Pass the pack through.** Do not summarize or paraphrase the JSON returned by the tool. Calling skills consume the structured pack directly.
- **Handle null `scan` cleanly.** When `scan === null` the workspace has no completed scan yet — surface that fact to the user and stop. Do not fabricate file paths or rules.
- **Read-only.** This skill does not edit files, the spec, or any PMCollab record.
- **Pack contains extracted facts, not file bytes.** If the calling workflow needs to compare against the live source, it should `Read` the files at the paths listed in `files[].path` from the local working directory.

## Step 1 — Validate inputs

Confirm both `workspaceId` and `useCaseId` are present. If not, delegate to `select-usecase`.

## Step 2 — Call the MCP tool

Invoke `code_load_context` with exactly:

```json
{ "workspaceId": "<workspaceId>", "useCaseId": "<useCaseId>" }
```

Parse the JSON-stringified text block returned in `content[0].text`.

## Step 3 — Hand the pack to the caller

Return the parsed pack to the calling skill. Surface a short human-readable confirmation in chat:

> "Loaded code context for **<useCase title>**: scan `<scan.type>` from `<scan.scannedAt>` (`<scan.repoIdentifier>`) · <files.length> files · <businessRules.length> business rules · <aiPrompts.length> AI prompts · <changeLog.length> change-log entries scoped to this use case."

When `scan === null`:

> "No completed code scan found for this workspace. Run a code scan in PMCollab first, then retry."

## Out of scope

- Rendering / diffing the extracted artifacts — leave that to the calling workflow.
- Reading the live local files — the calling workflow does that with its own `Read` tool.
- Filtering / trimming the pack — the server has already scoped to the use case.
- Editing anything (files, spec, capabilities, behaviors).
