---
name: process-queue
description: Pick an available Code Factory queue item, claim it for the caller, load the Claude starter kit (CLAUDE.md / SPEC.md / BUILD_PLAN.md / prompt.md), summarize the loaded spec, and draft an implementation plan for PM review. After the picker pushes the work as a PR, the skill can mark the queue item complete using the PR URL. Use when the user says "pick up a queue item," "process the next code factory task," "claim a queued code-gen job," or runs the namespaced slash command /pm:process-queue. Auto-chains select-workspace when no workspaceId is supplied.
---

# process-queue

Pick an active Code Factory queue item from a PMCollab workspace, claim it for the caller, pull down the Claude starter kit assets the picker needs to plan the work, give the user a quick TL;DR of the loaded spec, and have Claude draft an implementation plan for the PM to review **before** any code is written.

The skill's primary stopping point is "plan ready for review." After the plan is approved and the picker has actually implemented + pushed the work as a PR, the skill can also mark the queue item complete via `codefactory_queue_complete` with the PR URL — see Step 10. The skill still does NOT run the code-gen pipeline, push commits on the user's behalf, or release the item back to the pool.

## When to invoke

Trigger automatically when the user says any of:
- "Pick up a Code Factory queue item" / "Process the next code factory task"
- "Claim a queued code-gen job for me"
- "What's in the queue? I'll take one"
- They run the namespaced slash command `/pm:process-queue`

## Required inputs

- `workspaceId` — the workspace whose queue to read. If missing, this skill invokes `select-workspace` first.

## Hard rules

- **Never invent IDs.** Workspace ID, work item ID, and the artifact contents all come from MCP tool responses.
- **Don't claim something already claimed.** `codefactory_queue_pickup` returns a `conflict` error when someone else won the race — surface it and re-list instead of retrying blindly.
- **Don't write code or repo files during the planning phase.** Implementation is a separate, PM-approved step that happens after Step 9.
- **Don't call `codefactory_queue_release` from this skill.** Release is a user-driven decision; the skill never drops the work back to the pool on its own.
- **Only call `codefactory_queue_complete` in Step 10, after the picker confirms the PR URL.** Never invent a PR URL and never auto-complete a claim that has no shipped deliverable.

## Step 1 — Resolve workspace

If `workspaceId` is missing, invoke `select-workspace` first to resolve it, then continue. Do not call `codefactory_queue_list` without a `workspaceId`.

## Step 2 — List the active queue

Call `codefactory_queue_list` with the resolved `workspaceId` and no `status` filter. The tool defaults to the active set (`waiting_for_resources` / `in_progress` / `error`) — the same items the Code Factory Queue badge counts in the web UI.

If the response's `items` array is empty:

> "The Code Factory queue for `<workspace title>` is empty — nothing to pick up right now."

Stop.

Otherwise render a numbered list. For each item include:
- `name` (or `specDocumentId` if name is absent)
- status badge
- requester name + relative age (parse `requestedAt`)
- claimer name when status is `in_progress`
- short `notes` preview if present
- short `errorMessage` preview when status is `error`

Filter the picker UI to only the items the user can actually take next — items in `waiting_for_resources` (free to claim) and items in `error` (retryable). Items already `in_progress` and held by someone else should appear in the list but be marked "claimed by `<claimer>` — not pickable" so the user sees the queue state but can't pick them.

## Step 3 — User picks one

Ask:

> "Pick a number to claim, or type `cancel`."

On `cancel`, stop. Otherwise capture the chosen `itemId`.

## Step 4 — Claim it

Call `codefactory_queue_pickup` with the resolved `workspaceId` + the chosen `itemId`. Identity (`claimedBy` / `claimedByName`) is auto-resolved from the PAT context — do not prompt the user for it.

- On `conflict` error: someone else just claimed it. Re-call `codefactory_queue_list` and re-prompt — do not retry the pickup silently.
- On `not_found` error: the item was cancelled / deleted between list and pickup. Re-list and re-prompt.
- On success, confirm:

  > "Claimed **`<spec title or name>`** (`<itemId>`) for you. Fetching the Claude starter kit now."

## Step 5 — Fetch the Claude starter kit

Call `codefactory_queue_generate_deployment_target` with `workspaceId` + `itemId`. The response is a JSON envelope:

```
{
  "item": { "id", "specDocumentId", "useCaseId", "deploymentMode" },
  "bundle": {
    "files": [
      { "filename": "CLAUDE.md", "content": "..." },
      { "filename": "SPEC.md", "content": "..." },
      { "filename": "BUILD_PLAN.md", "content": "..." },
      { "filename": "prompt.md", "content": "..." }
    ]
  }
}
```

The deployment mode (`new_surface` vs `augment_existing`) determines what guidance is baked into `CLAUDE.md`. Honor it — don't propose scaffolding a fresh repo when the work item is `augment_existing`.

If the call fails with `not_in_progress`, surface the message and stop — something went wrong between the pickup in Step 4 and now (most likely the user released or completed it from another surface).

## Step 6 — Load assets into context

Treat each `bundle.files[i].content` value as the in-session contents for that filename when reasoning about the work:

- **`CLAUDE.md`** → project guidance, tech stack, file-size guidance, deployment-mode-specific instructions. This is your primary rulebook for the plan.
- **`SPEC.md`** → the actual spec the work item points at (the *what*).
- **`BUILD_PLAN.md`** → existing build-plan skeleton. Use as input and refine; do not start from scratch when this exists.
- **`prompt.md`** → an LLM-friendly rendering of the same spec for cross-reference.

Do not paste these files into chat in full unless the user asks — they're context, not output.

## Step 7 — Show the spec TL;DR

Before drafting the plan, surface a short orientation so the picker knows what they just claimed without scrolling through SPEC.md. Render in this exact shape:

```
**Spec TL;DR — <work item name or spec title>**
- **Goal:** <1 sentence — what this work item is trying to accomplish, distilled from SPEC.md>
- **Deployment mode:** `<augment_existing | new_surface>` — <1 phrase on what that implies>
- **Scope:** <1 sentence covering the main user-visible change or capability>
- **Key acceptance criteria:** <2–4 bullet fragments lifted from SPEC.md's acceptance criteria; "[none stated]" if absent>
- **Notable constraints / risks:** <1–3 fragments — performance, security, integrations, [Needs Input] gaps; "[none flagged]" if absent>
- **Picker notes:** <verbatim `notes` field from the work item; omit the line if empty>
```

Rules for the TL;DR:

- Pull every fact from the loaded `SPEC.md` / `BUILD_PLAN.md` / work item — do not infer goals from the spec title alone.
- Keep it under ~10 lines. The plan in Step 8 is where the depth goes.
- Mark `[Needs Input]` sections as such instead of guessing their contents.
- If `SPEC.md` is missing required sections (no acceptance criteria, no goal statement), say so explicitly — the picker may decide to release the item rather than plan against an incomplete spec.

## Step 8 — Draft the plan in plan mode

A skill cannot programmatically enter Claude Code's plan mode (it's an environment state, not a tool call). What to do instead:

1. If plan mode is not already active, tell the user:

   > "Recommend enabling plan mode for this session (Shift+Tab in Claude Code) — I'll defer all file writes and shell commands until the plan is reviewed."

2. Whether or not plan mode is active, behave as if it is for the remainder of this skill: produce a plan, write nothing to the repo, run no destructive commands.

3. Draft a structured implementation plan grounded in `CLAUDE.md` + `SPEC.md` + `BUILD_PLAN.md`. Sections to cover:
   - **Context** — what this work item is and why (one paragraph, distilled from `SPEC.md`).
   - **Files to modify / create** — concrete paths, mode-aware: in `augment_existing` mode survey existing modules first and preserve their structure; in `new_surface` mode propose the scaffold.
   - **Files to read for reuse (no edits)** — existing functions / utilities that should be reused instead of reimplemented.
   - **Implementation steps** — ordered, each step naming the concrete API / function / test it changes.
   - **Verification** — type-check / test commands, manual exercises, the acceptance criteria from the spec.
   - **Out of scope** — what this plan deliberately does NOT do, so reviewers don't expect it.

4. When plan mode IS active and a plan file path was provided, write the plan there. Otherwise post the plan in chat.

## Step 9 — Hand off for implementation

When the plan is ready, tell the user:

> "Plan drafted for **`<spec title>`** (queue item `<itemId>`). Review it; on approval, the picker (you or a follow-up agent) executes the plan, pushes the work as a pull request, and then comes back here so I can mark the queue item complete via `codefactory_queue_complete` with the PR URL. If you'd rather drop the work back to the pool, the picker can release it via `codefactory_queue_release`."

The skill does NOT auto-implement. Wait for the picker to explicitly confirm that a PR has been pushed before moving to Step 9.5.

## Step 9.5 — Reconcile any spec changes the picker negotiated

While implementing, the picker almost always negotiates the spec against the real code: it corrects implementation detail that bled into the spec inaccurately, and it intentionally drops scope (the plan's **Out of scope** section). Those decisions must get back into the spec — but most are routine, and the PM should only see the genuine product calls.

Trigger this step when the picker reports the PR (before Step 10), if the implementation diverged from `SPEC.md` in any way. If the picker confirms the code matches the spec exactly, skip to Step 10.

1. Collect the deltas the picker negotiated, each as one of:
   - **`kind: "change"`** — an edit to an existing spec item (a behavior, rule, or acceptance criterion the code implemented differently). Set `changeType` to `modification` / `removal`, `sectionHeading` to the spec section it touches, `beforeContent` to the existing text, `afterContent` to the corrected text.
   - **`kind: "out_of_scope"`** — something deliberately dropped (the plan's "intentionally dropped" list). Use `changeType: "addition"`, `sectionHeading` of the spec's Non-Goals / V1 Scope Boundary section, and put the dropped-scope note in `afterContent`.
   - For every delta give a one-sentence `rationale` and cite `codeProvenance` (file paths / the PR URL).
2. Call `codefactory_queue_propose_spec_changes` with `{ workspaceId, itemId, deltas }`. The backend runs an architect/APM triage on each delta:
   - **Auto-applied** deltas are committed straight to the spec as a new version — no PM action. Tell the user which were auto-applied.
   - **Escalated** deltas become a CoWorkStream spec-review item for the PM. When the response has `status: "escalated"`, **STOP here**: do NOT complete the queue item. Tell the user:

     > "`<n>` spec change(s) needed a product call and were sent to the PM as a spec-review item (`<reviewId>`). Completion is blocked until the PM resolves them — the item will return to the queue to be re-planned against the corrected spec. The PM can also override and complete as-is."

3. Only when the response is `status: "clear"` (everything auto-applied or no deltas) proceed to Step 10.

If you call `codefactory_queue_complete` while changes are still escalated it returns `error: "spec_reconciliation_pending"` — that's the gate working. Pass `override: true` only when the PM explicitly chooses to complete without reconciling (abandoning the proposed spec changes).

## Step 10 — Complete the queue item once a PR is up

Trigger when the user says any of:
- "PR is up: `<url>`" / "PR pushed, mark it done"
- "Complete the queue item with this PR"
- Replies to the Step 9 hand-off message with a GitHub / Azure DevOps pull-request URL

Required inputs at this step:
- `workspaceId` + `itemId` — carry forward from the earlier steps; do NOT re-prompt.
- `pullRequestUrl` — the URL the user just pasted. Validate that it is an `https://` URL pointing at a PR (GitHub `/pull/N`, Azure DevOps `/pullrequest/N`, etc.). If it does not look like a PR URL, ask the user to confirm before proceeding.
- `name` (optional) — defaults to the work item's name when omitted.

Call `codefactory_queue_complete` with `{ workspaceId, itemId, pullRequestUrl, name? }`. Do NOT pass `artifactId` — the backend creates a stub `CodeFactoryArtifact` (status `complete`, `pullRequestUrl` set) on the fly and links it to the queue card.

Error handling:

- `not_found` — the work item was deleted between Step 4 and now. Tell the user and stop.
- `not_in_progress` — the item was released, cancelled, or already completed. Surface the returned `currentStatus` and stop; do NOT silently re-claim.
- `missing_input` — defensive guard (the call shape is wrong). Re-prompt for the PR URL and retry once.
- `spec_reconciliation_pending` — Step 9.5 escalated spec changes the PM hasn't resolved yet. Do NOT auto-retry. Tell the user completion is blocked until the PM resolves the spec-review item (`reviewId` in the error), or re-call with `override: true` only if the PM explicitly chooses to complete without reconciling.

On success, confirm:

> "Marked queue item `<itemId>` complete. Linked to PR `<pullRequestUrl>` via artifact `<artifactId from response>`."

Then stop. The skill is done.

## Out of scope

- Running the in-app code-gen pipeline (the one that produces a full `CodeFactoryArtifact` with generated files).
- Implementing the spec for the user — the picker drives the implementation; this skill plans and books the completion.
- Calling `codefactory_queue_release` from this skill.
- Auto-completing without a PR URL the user has explicitly provided.
- Bulk-processing multiple queue items in one invocation — one item per run.
