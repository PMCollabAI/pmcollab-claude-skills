---
name: code-session-bind
description: "Bind the repository this session runs in to a PMCollab workspace so @Code mentions from that workspace reach this session. Use when the PMCollab mentions channel reports that the code-session token covers several workspaces, when the user says bind this repo to a workspace or switch the code session to another workspace, or when the user runs /pm:code-session-bind with a workspace id. Calls the bind_workspace tool of the code-session server; nothing is written into the repository."
---

# code-session-bind

Map the current repository to one PMCollab workspace for the **PMCollab mentions** channel (`@Code` in PMCollab routes to this session). The mapping is stored in the plugin's own data directory, keyed by the repository root. It is needed only when the code-session token covers more than one workspace — with a single-workspace token the server connects on its own.

## Hard rules

- **Never invent a workspace id.** It comes from the user's argument, from the list the code-session server printed (`Workspaces this token covers:`), or from the `workspace_list` tool of the `pmc-mcp` server.
- **Do not write any file yourself.** The `bind_workspace` tool owns the mapping; nothing goes into the repository.
- **Identity is not an argument.** The code-session token decides who the session belongs to.

## Step 1 — Resolve the workspace id

- If the user passed an id (`/pm:code-session-bind ws_123`), use it.
- Otherwise call `workspace_list` on `pmc-mcp`, show the workspaces as a numbered list, and ask the user to pick one. Wait for the answer.

## Step 2 — Bind

Call the `bind_workspace` tool of the `code-session` server (`mcp__plugin_pm_code-session__bind_workspace`) with `workspace_id` set to the chosen id.

## Step 3 — Report

Relay the tool's result in one or two sentences:

- **Connected** — say which workspace this repository is now bound to, and that `@Code` mentions from it will arrive here. If the result says permission relay needs a restart, pass that on.
- **On standby** — another session for this workspace is already receiving mentions and keeps them. This session takes over by itself when that one exits; to switch now, call the `take_over_mentions` tool of the `code-session` server (only if the user wants this session to receive mentions).
- **Refused** — quote the reason. For "does not cover that workspace", the token was minted for other workspaces: the user picks one of those, or mints a new code-session token in PMCollab (Workspace settings → Integrations → Code session).
- **No token configured** — the plugin's "PMCollab mentions" configuration has no code-session token yet. Point the user to the setup panel in PMCollab (Workspace settings → Integrations → Code session).
- **Tool not available** — the `code-session` server is not running; `/mcp` shows its status. After binding, mentions reach this session only when it was launched with the PMCollab mentions channel (the setup panel shows the launch command).
