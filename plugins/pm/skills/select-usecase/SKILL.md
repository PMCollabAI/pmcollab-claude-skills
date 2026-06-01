---
name: select-usecase
description: Pick a PMCollab use case from a resolved workspace, with keyword filtering for large lists (100+ use cases). Use after select-workspace, when another PMCollab skill says "select a use case," or when the user says "pick a use case" / "scope this to a use case." Requires workspaceId (auto-chains to select-workspace if missing). Optional intentKeywords pre-filters the list. Returns useCaseId + useCaseTitle (both undefined if the user chose "none / leave unscoped").
---

# select-usecase

Pick a PMCollab use case from a known workspace via the `pmc-mcp` MCP server. Designed for workspaces that may contain hundreds of use cases — filters by keyword before presenting choices so the chat doesn't get flooded.

## When to invoke

- After `select-workspace` has resolved a `workspaceId`.
- The user says "pick a use case," "scope this to a use case," or "switch use case."
- A workflow needs `useCaseId` but doesn't yet have it.

## Required inputs

The calling skill (or the conversation) should supply:

- `workspaceId` — the workspace to list use cases in.

If `workspaceId` is missing, invoke `select-workspace` first to resolve it, then continue. Do not attempt `workspace_list_usecases` without a `workspaceId`.

Optionally:

- `intentKeywords` — a short topic / keyword derived from the calling workflow's context (for example, `"time tracking auto-tagging"`). When supplied, used to pre-filter the list in Step 2 without re-prompting the user.

## Hard rules

- **Never invent IDs.** Every ID comes from an MCP tool response.
- **Don't dump 100+ use cases into chat.** If the list is large, filter first.
- **`useCaseId` is optional.** Honor "none" / "leave unscoped" as a valid final answer — return both fields as undefined.
- **Don't create new use cases.** This skill only selects existing ones.

## Step 1 — Fetch and assess size

Call `workspace_list_usecases` with the supplied `workspaceId`. Inspect the result:

- **≤ 15 use cases:** skip filtering — go straight to Step 3 and render the full numbered list.
- **> 15 use cases:** go to Step 2 first.

## Step 2 — Narrow the list (only when > 15)

If the caller supplied `intentKeywords`, substring-match (case-insensitive) against use-case titles and present the top 10 matches plus the count of how many didn't match. Skip the keyword prompt.

If you don't have `intentKeywords`, ask the user:

> "This workspace has <N> use cases. What's a keyword or topic that fits the use case you want? (Or type `list all` to browse, or `none` to leave unscoped.)"

Substring-match the answer (case-insensitive) against use-case titles. Show the top 10 matches:

```
Matches for "time" (3 of 142 use cases):
1. Time Tracking — 2 capabilities
2. Timesheet Approvals — 5 capabilities
3. Realtime Reporting — 0 capabilities

Pick a number, type a different keyword, type `list all` to browse, or `none`.
```

If `list all` is requested, paginate at 20 per page with `more` / `back` / `stop` controls.

If the user types a different keyword, re-filter and re-render.

## Step 3 — Confirm and capture

When the user picks a number (or says `none`), capture `useCaseId` and `useCaseTitle` (both undefined if `none`).

Report back:

> "Resolved use case: **Time Tracking** (`<useCaseId>`)."

or

> "Resolved: no use case scope — proceeding workspace-wide."

## Out of scope

- Creating a new use case (no `usecase_create` call here).
- Editing a use case's metadata, capabilities, or behaviors.
- Listing workspaces — that's `select-workspace`.
