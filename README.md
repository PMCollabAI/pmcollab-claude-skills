# PMCollab Claude Code Skills

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace published by [PMCollab, Inc.](https://pmcollab.ai). One plugin, every PMCollab workflow.

## Install

```
/plugin marketplace add pmcollabai/pmcollab-claude-skills
/plugin install pm@pmcollab-claude-skills
```

One install brings up 9 `/pm:<command>` slash commands and registers the shared `pmc-mcp` MCP server. See [`plugins/pm/README.md`](./plugins/pm/README.md) for the full command reference, PAT setup, and troubleshooting.

## Commands at a glance

| Command | What it does |
|--------|--------------|
| [`/pm:select-workspace`](./plugins/pm/commands/select-workspace.md) | Pick a PMCollab workspace and resolve `workspaceId`. |
| [`/pm:select-usecase`](./plugins/pm/commands/select-usecase.md) | Pick a use case (with keyword filtering for large lists). |
| [`/pm:load-usecase-context`](./plugins/pm/commands/load-usecase-context.md) | Load essentials + capabilities + CurrentSpec for one use case. |
| [`/pm:load-code-context`](./plugins/pm/commands/load-code-context.md) | Load extracted facts for the code backing one use case. |
| [`/pm:chat-to-usecase`](./plugins/pm/commands/chat-to-usecase.md) | Turn the current chat into a new `UseCase` with BXT bullets. |
| [`/pm:chat-to-spec-review`](./plugins/pm/commands/chat-to-spec-review.md) | Package the chat as a PMCollab spec and open a Spec Review. |
| [`/pm:quick-change`](./plugins/pm/commands/quick-change.md) | Make the edit immediately; capture a CHANGE_SPEC from the diff behind it. |
| [`/pm:spec-align`](./plugins/pm/commands/spec-align.md) | Reconcile spec-vs-code drift for one use case. |
| [`/pm:process-queue`](./plugins/pm/commands/process-queue.md) | Claim the next unit of Code Factory work — one item or a train of several — load its starter kits, draft a plan. |

Every command also ships as a same-named skill that auto-triggers on natural-language phrases — say "make this a use case" or "align the spec for this use case" and the matching flow runs without typing the slash form.

## Repo layout

```
.claude-plugin/marketplace.json   # marketplace catalog (one entry: pm)
plugins/pm/                       # the consolidated plugin
  .claude-plugin/plugin.json
  .mcp.json                       # pmc-mcp server registration
  commands/                       # /pm:<command> slash commands
  skills/                         # same-named auto-trigger skills
  hooks/                          # opt-in capture-nudge Stop hook
  README.md
```

## Source-of-truth

This plugin is authored and iterated inside the PMCollab product repo at `pmcollab-claude-plugins/` and mirrored to the public repo on release. To contribute a change, open a PR against the source repo; releases get pushed here.

## Migration from `pmc-*` plugins

This marketplace previously shipped 10 individual `pmc-*` plugins. They have been replaced by the single `pm` plugin. See the [Migration section in `plugins/pm/README.md`](./plugins/pm/README.md#migration-from-pmc--plugins) for the old-command → new-command mapping and uninstall steps.

## License

MIT — see [LICENSE](./LICENSE).
