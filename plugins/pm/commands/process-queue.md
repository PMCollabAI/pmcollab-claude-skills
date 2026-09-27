---
description: Pick up the next unit of Code Factory work — a single queue item OR a train of several items sharing one branch and one pull request — load the Claude starter kit for everything claimed, draft an implementation plan for PM review, and submit the finished pull request for PM approval without waiting on it. Offers to form a train when several waiting items look groupable.
---

# /pm:process-queue

Pick an active Code Factory queue item from a PMCollab workspace, claim it for the caller, pull down the Claude starter kit assets the picker needs to plan the work, give the user a quick TL;DR of the loaded spec, and have Claude draft an implementation plan for the PM to review **before** any code is written.

The command's primary stopping point is "plan ready for review." After the plan is approved and the picker has actually implemented + pushed the work as a PR, the command submits it for PM approval via `codefactory_queue_submit_for_approval` (Step 10) and **stops** — a pull request is a proposal awaiting a merge, not a finished deliverable, so a PM decides in PMCollab's WORK STREAM and this session never waits on that. The command still does NOT run the code-gen pipeline, push commits on the user's behalf, or release the item back to the pool.

**This is the only door.** A picker asks for work; it should not have to know the work's SHAPE before choosing where to ask. A unit is either a single queue item or a **train** — several items travelling in one branch, one pull request and one review — and the flow adapts to whichever the user picks. A member of a live train is never offered as individual work, and there is no separate train command; the full contract for the train path is in `skills/process-queue/SKILL.md` (every step carries a **▸ Train** note where it differs).

Three entry shapes: a **first pass** (steps 1–10 as written), **rework** — an item a PM previously sent back, revised on its existing PR branch rather than re-implemented (Step 6.5) — and a **train**, one claim over several items ending in a mandatory per-item mapping saying which members it actually delivered.

## Required inputs

- `workspaceId` — the workspace whose queue to read. If missing, this command runs `/pm:select-workspace` first.

## Hard rules

- **Never invent IDs.** Workspace ID, work item ID, and the artifact contents all come from MCP tool responses.
- **Don't claim something already claimed.** `codefactory_queue_pickup` returns a `conflict` error when someone else won the race — surface it and re-list instead of retrying blindly.
- **Don't write code or repo files during the planning phase.** Implementation is a separate, PM-approved step that happens after Step 9.
- **Don't call `codefactory_queue_release` from this command.** Release is a user-driven decision; the command never drops the work back to the pool on its own.
- **Never wait for the PM.** Once Step 10 has submitted the work, the item is out of your hands — do not poll, do not ask the user to sit tight, do not schedule a check-back.
- **Never invent a PR URL**, and never submit a claim that has no pushed deliverable.
- **`codefactory_queue_complete` is not the PR path.** It is for the in-app code-gen pipeline (`artifactId`); a `pullRequestUrl` passed to it just redirects into the same approval gate.
- **Rework revises, it never restarts.** On an item with a `rework` block: no second pull request, no re-planning what the PM did not object to.

## Step 1 — Resolve workspace

If `workspaceId` is missing, run `/pm:select-workspace` (see `commands/select-workspace.md`) first to resolve it, then continue. Do not call `codefactory_queue_list` without a `workspaceId`.

## Step 2 — List the active queue

Call `codefactory_queue_list` with the resolved `workspaceId` and no `status` filter. The tool defaults to the active set (`waiting_for_resources` / `in_progress` / `pending_approval` / `awaiting_spec_approval` / `error`) — the same items the Code Factory Queue badge counts in the web UI.

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
- a **`REWORK round <n>`** marker plus the newest `reworkRequests[]` reason when the item has been sent back

Filter the picker UI to only the items the user can actually take next — items in `waiting_for_resources` (free to claim, including rework items) and items in `error` (retryable). Items already `in_progress` and held by someone else appear marked "claimed by `<claimer>` — not pickable". Items in `pending_approval` appear marked "delivered — awaiting PM approval, not pickable": the work is done and a human owns the next move. Items in `awaiting_spec_approval` appear marked with their `statusMessage` (e.g. "waiting for 10 spec approvals — not pickable"): deliberately unassigned while the PM decides the spec changes the implementation proposed, and back in the pool as rework only if changes are wanted.

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

- If the response carries a non-null `rework` block, say so instead:

  > "Claimed **`<spec title or name>`** (`<itemId>`) — this is **rework round `<n>`**. There is already a pull request (`<pullRequestUrl>`) on branch `<branch>`; we revise that, we don't rebuild it."

  Then follow Step 6.5 as well as Step 6.

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
  },
  "rework": null
}
```

On a send-back the `bundle.files` array also carries a `REWORK.md` (first), and `rework` is non-null.

The deployment mode (`new_surface` vs `augment_existing`) determines what guidance is baked into `CLAUDE.md`. Honor it — don't propose scaffolding a fresh repo when the work item is `augment_existing`.

If the call fails with `not_in_progress`, surface the message and stop — something went wrong between the pickup in Step 4 and now (most likely the user released or completed it from another surface).

## Step 6 — Load assets into context

Treat each `bundle.files[i].content` value as the in-session contents for that filename when reasoning about the work:

- **`CLAUDE.md`** → project guidance, tech stack, file-size guidance, deployment-mode-specific instructions. This is your primary rulebook for the plan.
- **`SPEC.md`** → the actual spec the work item points at (the *what*).
- **`BUILD_PLAN.md`** → existing build-plan skeleton. Use as input and refine; do not start from scratch when this exists.
- **`prompt.md`** → an LLM-friendly rendering of the same spec for cross-reference.

Do not paste these files into chat in full unless the user asks — they're context, not output.

## Step 6.5 — If this is rework, plan the REVISION (not the implementation)

Trigger when Step 4 returned a `rework` block or the bundle contains `REWORK.md`. Skip on a first pass.

The item already has a delivered pull request; the PM asked for changes rather than throwing it away. Your job is the delta.

1. **Read `REWORK.md` first** — round number, the PM's reason, the requested modifications as a checklist, the PR URL, the branch, and every earlier round.
2. **Check out the existing branch** from `rework.branch`. Do not create a new branch and do not open a second pull request.
3. **Read the existing diff** before planning — most of the work is already there and was not objected to.
4. **Scope the plan to the send-back only.** Every plan item must trace to the `reason` or a listed modification. Disagree in the plan rather than silently skipping.
5. **Check `history` for repeats** — an objection in more than one round was not resolved last time; start there.
6. **Push to the same branch**, then go to Step 10 with a `summary` that answers each modification point by point.

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

A command cannot programmatically enter Claude Code's plan mode (it's an environment state, not a tool call). What to do instead:

1. If plan mode is not already active, tell the user:

   > "Recommend enabling plan mode for this session (Shift+Tab in Claude Code) — I'll defer all file writes and shell commands until the plan is reviewed."

2. Whether or not plan mode is active, behave as if it is for the remainder of this command: produce a plan, write nothing to the repo, run no destructive commands.

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

> "Plan drafted for **`<spec title>`** (queue item `<itemId>`). Review it; on approval, the picker executes the plan, pushes the work as a pull request, and comes back here so I can submit it for PM approval via `codefactory_queue_submit_for_approval`. Once submitted, this item is off our plate — the PM approves and merges it in PMCollab, or sends it back to the queue with their reasons."

The command does NOT auto-implement. Wait for the picker to confirm a PR has been pushed before moving to Step 10.

## Step 9.5 — Collect the spec deltas the picker negotiated

While implementing, the picker almost always negotiates the spec against the real code. Collect those deltas here and pass them to Step 10's single submission, so the PM gets **one** decision covering both the spec changes and the merge.

Collect each delta as one of:

- **`kind: "change"`** — an edit to an existing spec item. Set `changeType` to `modification` / `removal`, `sectionHeading` to the section it touches, `beforeContent` to the existing text, `afterContent` to the corrected text.
- **`kind: "out_of_scope"`** — something deliberately dropped. Use `changeType: "addition"`, the `sectionHeading` of the spec's Non-Goals / V1 Scope Boundary section, and put the dropped-scope note in `afterContent`.

Give each a one-sentence `rationale` and cite `codeProvenance` (file paths / PR URL). If the code matches the spec exactly, pass `deltas: []`. (`codefactory_queue_propose_spec_changes` still works standalone, but calling it separately then submitting runs reconciliation twice.)

## Step 10 — Submit for PM approval, then stop

Trigger when the user reports the PR ("PR is up: `<url>`", "submit the queue item", or a reply to Step 9 with a PR URL).

Required inputs:
- `workspaceId` + `itemId` — carry forward; do NOT re-prompt.
- `pullRequestUrl` — validate it looks like a PR URL (GitHub `/pull/N`, Azure DevOps `/pullrequest/N`). On a rework round this is the SAME PR as before.
- `summary` — what was built and anything the PM should weigh. On rework, how each requested modification was addressed.
- `deltas` — from Step 9.5; `[]` when the code matches the spec.

Call `codefactory_queue_submit_for_approval` with `{ workspaceId, itemId, pullRequestUrl, summary, deltas }`. The backend records the PR, triages the deltas (routine ones auto-apply to the spec; genuine product calls ride on the same approval), moves the item to `pending_approval` — or to `awaiting_spec_approval`, parked and unassigned, when anything escalated — posts a matching note on the pull request, and raises the WORK STREAM card. Report which status came back.

On success, confirm and **stop**:

> "Submitted **`<spec title>`** (`<itemId>`) for PM approval on `<pullRequestUrl>`. `<n>` routine spec change(s) auto-applied; `<m>` need a product call and ride on the same decision. This item is off our plate. What's next?"

Do NOT poll for the outcome, do NOT call `codefactory_queue_complete`, and do NOT tell the user to wait.

Error handling:

- `not_found` — the work item was deleted. Tell the user and stop.
- `not_in_progress` — released, cancelled, or completed elsewhere. Surface `currentStatus` and stop; do NOT silently re-claim. (`pending_approval` is not an error — a re-submission refreshes the open gate. `awaiting_spec_approval` means it is already parked on the PM's spec decisions: report and stop.)
- `conflict` — a concurrent transition. Re-list and report; do not retry blindly.

### When the PM sends it back

The item returns to `waiting_for_resources` carrying the PM's reasons and requested modifications. The next `/pm:process-queue` run picks it up as rework (Step 4 → Step 6.5); the `rework` block is the whole hand-off, so nothing has to be remembered across sessions.

### Completing without the gate

`codefactory_queue_complete` with `override: true` completes an item outright — no approval, no merge, escalated spec changes abandoned. For the case where the PR was already merged by hand. Use only when the user explicitly asks, and say what it skips.

## Out of scope

- Running the in-app code-gen pipeline (the one that produces a full `CodeFactoryArtifact` with generated files).
- Implementing the spec for the user — the picker drives the implementation; this command plans and books the hand-off.
- Calling `codefactory_queue_release` from this command.
- Submitting without a PR URL the user has explicitly provided.
- **Waiting on, polling for, or reporting the PM's approval decision.** The gate is asynchronous by design.
- Approving or merging on the PM's behalf.
- Running the in-app Code Factory agent lane, which runs trains by its own path with its own preflight.
- Dissolving a train on your own initiative, or editing a committed train's membership — a train that will never run must be dissolved or its members stay locked; when the user asks, `codefactory_train_dissolve` does it (workspace admins only), and a new grouping is a fresh compose.
- Forming a train the user has not agreed to, or forming one as a side effect of looking for work.
