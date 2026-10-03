# pm — PMCollab Claude Code suite

A single Claude Code plugin that bundles every PMCollab workflow as a `/pm:<command>` slash command, with the shared `pmc-mcp` MCP server registered automatically. One install gives you the whole surface.

## Install

```
/plugin marketplace add pmcollabai/pmcollab-claude-skills
/plugin install pm@pmcollab-claude-skills
```

That's it — there are no other plugins to chain.

## Commands

| Command | What it does |
|--------|--------------|
| [`/pm:select-workspace`](./commands/select-workspace.md) | Pick a PMCollab workspace and resolve `workspaceId` for the session. |
| [`/pm:select-usecase`](./commands/select-usecase.md) | Pick a use case from a resolved workspace, with keyword filtering for large lists. Accepts an optional keyword argument. |
| [`/pm:load-usecase-context`](./commands/load-usecase-context.md) | Load a tight LLM-context pack (essentials + capabilities + CurrentSpec) for one use case via one MCP call. |
| [`/pm:load-code-context`](./commands/load-code-context.md) | Load a per-file extracted-facts pack (business rules + AI prompts + MCP/A2A endpoints + change-log) for the code backing one use case. |
| [`/pm:chat-to-usecase`](./commands/chat-to-usecase.md) | Turn the current Claude chat into a brand-new `UseCase` with BXT detail bullets. Greenfield companion to `chat-to-spec-review`. |
| [`/pm:chat-to-spec-review`](./commands/chat-to-spec-review.md) | Package the current Claude conversation as a PMCollab spec and kick off a Spec Review with Sphinx / Phoenix / Chimera. |
| [`/pm:quick-change`](./commands/quick-change.md) | Express path: make the requested code edit immediately, then capture a CHANGE_SPEC from the diff behind it (reviewers run async, commit stamped with a `Change-Spec:` trailer). |
| [`/pm:spec-align`](./commands/spec-align.md) | Reconcile spec-vs-code drift for one use case end-to-end (load spec + code contexts + live files, propose per-finding actions). |
| [`/pm:process-queue`](./commands/process-queue.md) | Pick up the next unit of Code Factory work — one item, or a **train** of several sharing one branch and one PR — load the starter kits, draft a plan for PM review, and submit on PR. Offers to form a train when items look groupable. |

## Skills — natural-language triggers

Every command also ships as an auto-trigger skill under [`./skills/`](./skills/). You don't have to type `/pm:` — saying any of the trigger phrases below in chat will activate the matching skill:

| Skill | Representative trigger phrases |
|------|--------------------------------|
| `select-workspace` | "pick a workspace," "switch PMCollab workspaces," "use a different workspace" |
| `select-usecase` | "pick a use case," "scope this to a use case," "switch use case" |
| `load-usecase-context` | "load the spec for this use case," "pull down the use case context" |
| `load-code-context` | "pull down the code snapshot," "load the related files," "show me what code touches this use case" |
| `chat-to-usecase` | "make this a use case," "add this to PMCollab as a use case," "create a use case for this" |
| `chat-to-spec-review` | "send this to PMCollab," "make a spec out of this," "open a spec review" |
| `quick-change` | "just fix this," "quick change," "make this edit," "small tweak to X" |
| `spec-align` | "align the spec for this use case," "check spec drift," "reconcile spec vs code" |
| `process-queue` | "pick up a queue item," "process the next code factory task," "claim a queued code-gen job," "batch these into one PR," "form a train" |

Both forms run the same flow. Slash commands are for users who already know what they want; skills are for users describing what they want in their own words.

### Routing between quick-change and chat-to-spec-review

Both produce the same CHANGE_SPEC artifact and lifecycle — the difference is whether review gates the code or trails it. `quick-change` is for thin-context, well-scoped edits: the code change lands first and the spec is captured behind it. `chat-to-spec-review` is for changes that grew out of a design conversation worth harvesting, and for anything over quick-change's scope ceiling (>~5 files, multiple use cases, spec-linked surfaces, no promoted baseline) — quick-change escalates there automatically, carrying its draft along.

## Capture nudge (opt-in Stop hook)

The plugin ships a `Stop` hook that reminds you — once per stop, never looping — when a session is about to end while the repo has uncommitted changes or unpushed commits with no `Change-Spec:` trailer. It suggests capturing via `/pm:quick-change` or `/pm:chat-to-spec-review`; declining is fine (PMCollab's PR-side drift detection remains the backstop).

It is **off by default**. Enable per repo:

```bash
git config pmc.captureNudge true
```

Disable again with `git config --unset pmc.captureNudge`.

## Auth setup

The bundled `.mcp.json` points at `https://pmcollab.ai/mcp/pmc` and uses **OAuth** — no token to paste.

### Testing against a non-prod environment

The MCP URL resolves from the `PMC_MCP_URL` environment variable, falling back to `https://pmcollab.ai/mcp/pmc` when unset:

```bash
export PMC_MCP_URL=http://localhost:5000/mcp/pmc
```

Set it before starting Claude Code (or in your shell profile), then restart Claude Code and run `/mcp` — `pmc-mcp` reconnects against the URL you set. Unset the variable (or set it back to the prod URL) to return to production.

### Default: OAuth (recommended)

The bundled `.mcp.json` declares `pmc-mcp` as a native remote HTTP server —
no bridge process, no third-party npm dependency. PMCollab is itself an
OAuth 2.1 Authorization Server for MCP (RFC 8414 / RFC 9728 discovery,
dynamic client registration), so Claude Code discovers and drives the
authorization-code flow directly against `pmcollab.ai`. Tokens are held and
refreshed by Claude Code's own OAuth state; there is nothing to configure.

1. Restart Claude Code, then run `/mcp` in a new session. `pmc-mcp` shows **needs auth** (or opens a browser automatically).
2. Sign in with your PMCollab account and approve the consent screen.
3. `pmc-mcp` flips to **connected** with the workspace / idea-chat / spec-document / spec-review / capability tool families enumerated.

Smoke test: `/pm:select-workspace` should return your workspace list.

Claude.ai / Claude Desktop users can add `https://pmcollab.ai/mcp/pmc` as a custom remote
connector — it's the same native OAuth 2.1 server, no plugin required.

### Headless / CI environments

The bundled configuration signs in through the browser, which a non-interactive
environment cannot do. `pmc-mcp` also accepts a Personal Access Token for those
cases — mint one from [pmcollab.ai](https://pmcollab.ai) under **Personal Access
Tokens**, where the setup steps live. This plugin ships no credential
configuration of its own: nothing here reads a token from your machine.

### Troubleshooting

- **Browser didn't open / stuck on "needs auth":** run `/mcp` and trigger reconnect, or clear cached OAuth state and retry.
- **"Spec Review not available at current maturity stage" (403):** the chat container the workflow creates starts at `spark`. The commands pass `maturityStage: 'shaping'` when starting the review. If you still see this error, the workspace may have a stricter gate — run `ideachat_assess_maturity` first.
- **`401 invalid token`:** the OAuth access token expired and refresh failed (or a PAT was revoked) — reconnect via `/mcp` to re-run the OAuth flow, or generate a fresh PAT.

## Migration from `pmc-*` plugins

This plugin **supersedes** the 10 individual `pmc-*` plugins that used to ship in this marketplace (`pmc-mcp`, `pmc-select-workspace`, `pmc-select-usecase`, `pmc-load-usecase-context`, `pmc-load-code-context`, `pmc-chat-to-usecase`, `pmc-chat-to-spec-review`, `pmc-spec-align`, `pmc-process-queue`, `pmc-suite`). Each old plugin is now a command in `pm`:

| Old slash command | New slash command |
|---|---|
| `/pmc-select-workspace:pmc-select-workspace` | `/pm:select-workspace` |
| `/pmc-select-usecase:pmc-select-usecase` | `/pm:select-usecase` |
| `/pmc-load-usecase-context:pmc-load-usecase-context` | `/pm:load-usecase-context` |
| `/pmc-load-code-context:pmc-load-code-context` | `/pm:load-code-context` |
| `/pmc-chat-to-usecase:pmc-chat-to-usecase` | `/pm:chat-to-usecase` |
| `/pmc-chat-to-spec-review:pmc-chat-to-spec-review` | `/pm:chat-to-spec-review` |
| `/pmc-spec-align:pmc-spec-align` | `/pm:spec-align` |
| `/pmc-process-queue:pmc-process-queue` | `/pm:process-queue` |

To migrate:

```
/plugin uninstall pmc-mcp
/plugin uninstall pmc-select-workspace
/plugin uninstall pmc-select-usecase
/plugin uninstall pmc-load-usecase-context
/plugin uninstall pmc-load-code-context
/plugin uninstall pmc-chat-to-usecase
/plugin uninstall pmc-chat-to-spec-review
/plugin uninstall pmc-spec-align
/plugin uninstall pmc-process-queue
/plugin uninstall pmc-suite
/plugin marketplace update pmcollabai/pmcollab-claude-skills
/plugin install pm@pmcollab-claude-skills
```

The MCP-server identifier (`pmc-mcp`, as shown in `/mcp`) is unchanged — your existing credentials continue to work without modification.

## License

MIT — see the [marketplace LICENSE](../../LICENSE).
