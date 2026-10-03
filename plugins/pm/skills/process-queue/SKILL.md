---
name: process-queue
description: Pick up the next unit of Code Factory work — a single queue item OR a train of several items that travel in one branch and one pull request — claim it, load the Claude starter kit (CLAUDE.md / SPEC.md / BUILD_PLAN.md / prompt.md) for everything claimed, confirm the deployment profile, summarize what was loaded, and draft an implementation plan for PM review. Offers to FORM a train when several waiting items look groupable. After the picker pushes the work as a PR, the skill submits it for PM approval and ENDS — it never waits. Handles rework — an item a PM sent back is revised on its existing PR branch, not re-implemented. Use when the user says "pick up a queue item," "process the next code factory task," "claim a queued code-gen job," "what is in the queue," "batch these into one PR," or runs the namespaced slash command /pm:process-queue. Auto-chains select-workspace when no workspaceId is supplied.
---

# process-queue

Pick up the next unit of Code Factory work from a PMCollab workspace, claim it for the caller, pull down the Claude starter kit assets the picker needs to plan the work, give the user a quick TL;DR of what was loaded, and have Claude draft an implementation plan for the PM to review **before** any code is written.

**This is the only door.** A picker asks for work; it should not have to know the work's SHAPE before choosing where to ask. A unit of work is either a single queue item or a **train** — several items that travel together in one branch, one pull request and one review — and the flow below adapts to whichever the user picks. There is no separate train command, and a member of a live train is never offered as individual work.

The skill's primary stopping point is "plan ready for review." After the plan is approved and the picker has actually implemented + pushed the work as a PR, the skill calls `codefactory_queue_submit_for_approval` (Step 10) and **stops**. A pull request is not a finished deliverable — it is a proposal awaiting a merge — so the queue item moves to `pending_approval` and a PM decides in PMCollab's WORK STREAM. **The session never waits for that decision.** The skill still does NOT run the code-gen pipeline, push commits on the user's behalf, or release the item back to the pool.

Three entry shapes, and the differences matter:

- **First pass** — a `waiting_for_resources` item nobody has delivered yet. Steps 1–10 as written.
- **Rework** — an item a PM previously sent back. `codefactory_queue_pickup` returns a `rework` block and the starter kit gains a `REWORK.md`. You are **revising an existing pull request branch**, not starting over. See Step 6.5.
- **A train** — one claim over several items, one plan, one branch, one PR, and a mandatory per-item mapping saying which members it actually delivered. Every step below carries a **▸ Train** note where it differs; where there is no note, the train path is identical.

The value of a train is review economics: five small hotfixes as five items cost five branches, five PRs and five PM approvals; as a train they cost one of each. That is also why membership caps at `MAX_TRAIN_ITEMS` (6) — past that the single PR stops being reviewable and the saving turns into a cost.

## When to invoke

Trigger automatically when the user says any of:
- "Pick up a Code Factory queue item" / "Process the next code factory task"
- "Claim a queued code-gen job for me"
- "What's in the queue? I'll take one"
- "Batch these into one PR" / "Do these fixes together" / "Form a train"
- They run the namespaced slash command `/pm:process-queue`

## Required inputs

- `workspaceId` — the workspace whose queue to read. If missing, this skill invokes `select-workspace` first.

## Hard rules

- **Never invent IDs.** Workspace ID, work item ID, and the artifact contents all come from MCP tool responses.
- **Don't claim something already claimed.** `codefactory_queue_pickup` returns a `conflict` error when someone else won the race — surface it and re-list instead of retrying blindly. **A train conflict is not a lost race.** A message naming a train ("This work item is part of train …") means the item is locked to a group; re-listing and re-picking it loops forever. Offer the TRAIN instead, per Step 4.
- **Never offer a trained member as individual work.** An item carrying a `trainId` whose train is live is `waiting_for_resources` and unclaimed, so it looks free and is not. Step 2 collapses it into its train's row.
- **Don't write code or repo files during the planning phase.** Implementation is a separate, PM-approved step that happens after Step 9.
- **Don't call `codefactory_queue_release` from this skill.** Release is a user-driven decision; the skill never drops the work back to the pool on its own.
- **Never wait for the PM.** Once Step 10 has submitted the work for approval, the item is out of your hands. Do not poll `codefactory_queue_list`, do not ask the user to sit tight, do not schedule a check-back. Report the hand-off and move on to whatever the user wants next.
- **Never invent a PR URL**, and never submit a claim that has no pushed deliverable.
- **`codefactory_queue_complete` is not the PR path.** It is for the in-app code-gen pipeline (`artifactId`). Passing a `pullRequestUrl` to it just redirects into the same approval gate; call `codefactory_queue_submit_for_approval` directly.
- **Rework revises, it never restarts.** On an item with a `rework` block: do not open a second pull request, do not re-plan sections the PM did not object to, and do not force-push over the branch's history unless a listed modification asks for it.
- **Never invent a tech stack.** An item whose starter kit reports `deploymentProfile.status: "none"` has no recorded stack and nothing could be derived from its repository, so `CLAUDE.md` is missing its Tech Stack / Commands / Project Structure sections. Resolve it through Step 5.5 — never fill the gap with your own defaults, and never create a deployment profile the user has not explicitly accepted. `status: "derived"` is the opposite case and is **not** a blocker: the stack in `CLAUDE.md` came out of the repository's own manifests, so build to it and offer to record it.
- **Never repoint the workspace default yourself.** `codefactory_queue_set_deployment_profile` owns that call: it adopts the profile only when the workspace has none, and raises a PM decision when a different default already stands. Report which happened; don't try to force the other.
- **▸ Train — one branch, one PR, for the whole train.** A train that opens two pull requests is not a train; it is the individual flow with extra steps, and it splits the review the train existed to consolidate.
- **▸ Train — never compose a grouping the user has not agreed to.** Formation is user-driven by design: the system proposes, a human commits. Never form a train as a side effect of looking for work.
- **▸ Train — never compose over a `needs_review` verdict without a real justification.** `overrideJustification` is recorded on the train and read months later by whoever is confused by the PR. "Batching for efficiency" is not a justification; naming what the changes share is.
- **▸ Train — `codefactory_train_compose` is NOT retry-safe.** Every call mints a new train. After a timeout or an ambiguous failure, call `codefactory_train_get` before ever calling compose again — a blind retry leaves two trains fighting over the same locked items.
- **▸ Train — work only what the claim says you hold.** An id in `unclaimedItemIds` belongs to another run: do not implement it, do not mention it in the PR, do not mark it delivered.
- **▸ Train — per-item results are mandatory and must be honest.** A train that delivered three of five says exactly that; the two return to the pool to be re-trained. Marking a miss `delivered` to make the run look clean silently loses the work.
- **▸ Train — never dissolve a train the user did not ask you to dissolve.** Dissolution releases every member back to individual pickup; it is a user decision, not a recovery step you take on your own.

## Step 1 — Resolve workspace

If `workspaceId` is missing, invoke `select-workspace` first to resolve it, then continue. Do not call `codefactory_queue_list` without a `workspaceId`.

## Step 2 — List the work, as UNITS

Call `codefactory_queue_work_units` with the resolved `workspaceId`. **One call, and pickability is already decided** — do not re-derive it.

The server answers this, not the skill, and deliberately so: "can this be worked?" was reimplemented on three surfaces before it was stamped, and every copy lost the same clause. A `trainId` is a POINTER, not a lock — a train that was submitted, abandoned, deleted or left to lapse holds nothing — so an item that looks trained may be perfectly free, and a member of a LIVE train looks free and is not. The rule lives in `backend/src/services/codeFactory/queueWorkUnits.ts`; read the answer.

Each unit carries:

- `kind` — `train` (ONE unit carrying several items; its members never appear separately) or `item`
- `id`, `name`, `itemIds`
- `pickable`, and when false a `notPickableCode` + a `notPickableReason` sentence written to be shown
- `trainEligible` on a loose item — whether it could join a train (Step 2.5)

If `units` is empty:

> "The Code Factory queue for `<workspace title>` is empty — nothing to pick up right now."

Stop.

### Render what came back

Show every unit, pickable or not — a picker needs to see the queue, not just their slice of it — and mark the rest with its `notPickableReason` verbatim. Trains first, then loose items.

```
<n>. **Train: <name>** (`<id>`) — <m> items
     <one line per member id>
<n>. <name> — <status>, requested <relative age> by <requester>
```

Two `notPickableCode` values need more than a label:

- **`train-member`** — never becomes pickable by re-reading, and a picker that retries it loops. Offer that member's TRAIN as the unit instead, or — if the user says that train should not run — dissolve it with `codefactory_train_dissolve` so its members can be worked on their own.
- **`train-in-flight`** — a run holds the train until the named expiry. Not yours; do not compose a competing train over the same files.

Everything else (`claimed-by-other`, `agent-lane`, `delivered`, `awaiting-spec-approval`, `not-open`) renders as its reason and nothing more.

Add from the item record, for the rows that have them: a short `notes` preview, a short `errorMessage` preview on `error`, and a **`REWORK round <n>`** marker plus the newest `reworkRequests[]` reason on a send-back — that last one is the most important thing on its row, because it changes what claiming the item means.

### Detail to pull from the item records

`codefactory_queue_work_units` answers *what can be picked up*; it is not the full item record. When a row needs more than its name and reason, call `codefactory_queue_list` and read the matching item. For each row that will be shown:
- `name` (or `specDocumentId` if name is absent)
- status badge
- requester name + relative age (parse `requestedAt`)
- claimer name when status is `in_progress`
- short `notes` preview if present
- short `errorMessage` preview when status is `error`
- a **`REWORK round <n>`** marker plus the newest `reworkRequests[]` reason when the item has been sent back — this is the single most important thing on the row, because it changes what claiming the item means

Filter the picker UI to only the items the user can actually take next — items in `waiting_for_resources` (free to claim, including rework items) and items in `error` (retryable).

One exception inside `waiting_for_resources`: an item carrying `agentAssignment` with `state: "queued"` has been handed to PMCollab's **in-app Code Factory agent** and is waiting its turn in that lane. It is not free work — list it marked "queued for the Code Factory agent — not pickable". `codefactory_queue_pickup` refuses it with a `conflict` telling you to unassign the agent first, which a PM does from the queue card in the web UI. Items whose assignment is `starting` / `running` are already `in_progress` and excluded by the rule above; `state: "failed"` or `"cancelled"` means the agent is off the item and it IS pickable. Items already `in_progress` and held by someone else should appear in the list but be marked "claimed by `<claimer>` — not pickable". Items in `pending_approval` should appear marked "delivered — awaiting PM approval, not pickable": the work is done and a human owns the next move, so claiming it would duplicate a PR that already exists. Items in `awaiting_spec_approval` are the same, marked with their `statusMessage` (e.g. "waiting for 10 spec approvals — not pickable"): they are deliberately unassigned, but that does not make them free work — the PM's decisions have to land first, and they come back to the pool as rework if changes are wanted.

## Step 2.5 — Offer to FORM a train when the shape is there

Only when **two or more** units came back with `trainEligible: true`. Skip it entirely otherwise — an offer on every listing is noise, and a picker who wanted one item does not want a grouping exercise.

`trainEligible` is the server's answer, decided on the same predicate composition itself refuses membership on: open, unassigned, untrained, and backed by something that states the requirement. Do not re-derive it, and do not talk a user into a grouping the flag says is impossible — `codefactory_train_compose` will refuse the whole call and name the item.

**Hotfixes are the point, not the exception.** Several small fixes in one branch and one review is the case a train is built for, and the server marks them eligible: a ticket escalation carries a `TICKET.md` and a known-issue escalation an `ISSUE.md`, and both render a real starter kit. Never filter escalations out for lacking a spec.

Make it one line, and make it declinable:

> "Items 2, 4 and 5 look like they could ship together (`<what they share>`). Want them as one branch and one PR? (`train 2 4 5` / just pick a number)"

If the user says yes:

1. **Evaluate before committing anything.** Call `codefactory_train_evaluate` with the `workspaceId` and the chosen `itemIds`. Nothing is written and nothing is locked, so call it freely while narrowing — this is the cheap step, and composing without it is how a bad grouping becomes a locked one.
   - **`eligible`** → compose freely; say what the judge found they share.
   - **`needs_review`** → composable, but only with a written justification. Show `conflictFindings` and `dependencyFindings` and ask the user *why* these belong together. Their words become `overrideJustification`.
   - **`ineligible`** → refused. Report `rationale` and offer to drop the offending item or split into two trains. Do not attempt to compose.
   - **Check `evaluation.path` before trusting any of it.** `fallback` means the check **did not run** — the model was unreachable — and the verdict is a placeholder, not an assessment. Say so in exactly those terms: a `needs_review` on the fallback path is "nobody looked", not "we looked and were unsure".
2. **Compose.** Call `codefactory_train_compose` with `{ workspaceId, itemIds, name, overrideJustification }`. Write a real `name` ("Three export hotfixes") — the default is a count of the changes, which is worse. On `composed: false` with `requiresJustification: true`, go back to the question above; do not invent a rationale. An error naming a specific item refuses the **whole call**, so fix that item and call again.
3. **Then pick it up** — the new train is the unit; continue at Step 4. Composing is not running, and a train nobody claims holds its members locked.

Cap the selection at **6**. If the user names more, say why the cap exists and ask them to split.

## Step 3 — User picks one

Ask:

> "Pick a number to claim, or type `cancel`."

On `cancel`, stop. Otherwise capture the chosen unit — an `itemId`, or a `trainId` when they picked a train row.

## Step 4 — Claim it

### ▸ Train — claim the whole train

Call `codefactory_train_claim` with `{ workspaceId, trainId }`. Omit `stillOpenItemIds` unless you have a reason to **narrow** the claim; the server re-reads the queue itself, and its read is fresher than anything you could pass.

One call does both halves: it takes the train's lease **and** claims every member still open, so each reaches `in_progress`. That matters concretely — a member's starter kit is only generatable once it is `in_progress`, and the kit is where the AI Constitution, the Implementation Patterns, the adopted codebase skills and the deployment profile live.

- `claimed: true`, `resumed: false` → you hold the train. **`items` is the run's real scope**, and it may be shorter than the train listed.
- `claimed: true`, `resumed: true` → you already held this lease from an earlier session. Carry on from where that run stopped; do not re-claim, and do not compose anything.
- `claimed: false` → read `reason` (another run's live lease, or every member resolved since commit). Report it and stop; do not retry blindly.

A non-empty `unclaimedItemIds` is stated **before** planning, not after:

> "Claimed `<n>` of `<m>` members. `<ids>` were taken by another run and are **not** in this train's scope — I'll map them `not-delivered` at submit."

Then continue at Step 5, once per member.

### Single item

Call `codefactory_queue_pickup` with the resolved `workspaceId` + the chosen `itemId`. Identity (`claimedBy` / `claimedByName`) is auto-resolved from the PAT context — do not prompt the user for it.

- On `conflict` error, read the message before reacting — the two conflicts need opposite responses:
  - **Named a train** ("This work item is part of train …") → the item is locked to a group, not lost to a race, and re-listing will not change that. Step 2 should have made this unreachable by never offering the member; if you see it, you picked from a stale listing. Re-read `codefactory_queue_work_units` and offer that member's TRAIN as the unit — never the member again.
  - **Anything else** → someone else just claimed it. Re-call `codefactory_queue_list` and re-prompt; do not retry the pickup silently.
- On `not_found` error: the item was cancelled / deleted between list and pickup. Re-list and re-prompt.
- On success, confirm:

  > "Claimed **`<spec title or name>`** (`<itemId>`) for you. Fetching the Claude starter kit now."

- If the response carries a non-null `rework` block, say so instead:

  > "Claimed **`<spec title or name>`** (`<itemId>`) — this is **rework round `<n>`**. There is already a pull request (`<pullRequestUrl>`) on branch `<branch>`; we revise that, we don't rebuild it. Fetching the starter kit + the rework brief now."

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
  }
}
```

…plus a `deploymentProfile` block (see Step 5.5) and, on a send-back, a `rework` block.

The deployment mode (`new_surface` vs `augment_existing`) determines what guidance is baked into `CLAUDE.md`. Honor it — don't propose scaffolding a fresh repo when the work item is `augment_existing`.

If the call fails with `not_in_progress`, surface the message and stop — something went wrong between the pickup in Step 4 and now (most likely the user released or completed it from another surface).

**▸ Train — once per member.** Call it for every item in the claim's `items`, and load each kit under its member's id. A member carrying a `rework` block does not belong in a train: it has to revise **its own** PR, and a train produces one new one. Say so and offer to drop it from the run and handle it as a single item instead.

## Step 5.5 — Confirm the deployment profile BEFORE planning

The **deployment profile** is the recorded tech stack, delivery surfaces and build target the work is generated against. It is what fills `CLAUDE.md`'s `## Tech Stack`, `## Commands`, `## Coding Conventions` and `## Project Structure`. When an item has none and nothing could be derived, those sections are absent or generic — and an agent that plans anyway is choosing a stack for the product by itself, silently, one queue item at a time. That is the single most expensive thing this skill can get wrong, because nothing downstream flags it.

Read `deploymentProfile` off the Step 5 response and branch on `status`. There are **three** states, and the middle one is the common case on an existing codebase:

| `status` | What the kit carries | What you do |
|---|---|---|
| `resolved` | A recorded deployment profile's stack | Build to it. |
| `derived` | The stack the repository was **observed** to have, read from its own project manifests | Build to it, and offer to record it. **Not** a blocker. |
| `none` | No stack at all | Work the ladder before planning. |

**▸ Train — the members must AGREE on one profile.** Every member builds on one branch, so one branch cannot be two stacks. All `resolved` and identical is fine; two different profiles is a grouping error the compatibility judge does not catch — report the split and offer to drop the odd member or split the train, rather than picking one and hoping. A train whose members are all `derived` is not a split — they share one product, so they share one observation. Resolve any `status: "none"` by the ladder below exactly as for a single item.

### `status: "resolved"`

Say which profile is in force and move on:

> "Building against deployment profile **`<name>`** — `<stackSummary>`."

When `source` is `workspace_default` (the item recorded no profile of its own), add one line: the workspace's default applied, so confirm it fits this surface before planning against it. When `source` is `work_item`, the PM filed the item under it — build to it, don't substitute.

### `status: "derived"` — the repository already answered; build to it

This is what you get on an **existing codebase** that has been scanned but whose PM has never opened the deployment-profile dialog. `observedStack` carries the stack the platform read out of the repository's own project manifests — framework, version, and the `.csproj` / `package.json` / `pyproject.toml` that declares each one — and `CLAUDE.md` was rendered from it.

**Do not stop and ask.** The stack is not a decision anyone is waiting on; it is the customer's own code. Stopping to run the "design a profile" ladder over a repository you can see in front of you is the failure this state was added to remove — most visibly on work that only adds tests, where the test project is right there in the observation.

Say what you are building to, in one line, and keep going:

> "No deployment profile is recorded, so I'm building to the stack this repository was observed to have: `<observedStack.stackSummary>`. (`<observedStack.note>`)"

Then, in the same message, offer to record it — one question, not a design session:

> "Want me to save that as this product's deployment profile so future queue items carry it? (`yes` / `not now`)"

On `yes`: call `codefactory_deployment_profile_suggest` (it is seeded with the same observation — `groundedInRepoScan: true` in the response confirms it), show what comes back, and on acceptance `codefactory_deployment_profile_create` → `codefactory_queue_set_deployment_profile` → report the default branch, exactly as steps 3–5 below. On `not now`: proceed with the plan and say once, in the plan, that the stack is observed rather than recorded.

**Two hard rules still hold.** The observation is authoritative for matching what is already there — its frameworks, its test project, its conventions. It is **not** licence to introduce a technology the repository does not already use: that is a question for the requester, same as it would be under a recorded profile. And never substitute a stack of your own for the observed one.

### `status: "none"` — resolve it, never invent one

This means the product has no profile **and** nothing could be derived — its repository has not been scanned, or the scan detected no stack. There is genuinely nothing to build to.

**Hard rule: do not choose a stack yourself, and do not create a profile without the user explicitly accepting it.** Work the ladder:

1. **Look at what exists.** Call `codefactory_deployment_profile_list` with the `workspaceId` (the Step 5 `candidates` array is the same data if you already have it). Judge each against what `SPEC.md` actually describes — the delivery surface first (a web app profile does not fit a mobile surface), then the stack.

2. **If one fits, confirm it.** Never attach silently:

   > "This work item has no deployment profile, so `CLAUDE.md` shipped without a tech stack. **`<name>`** (`<stackSummary>`) looks like the right fit because `<one sentence tied to the spec>`. Use it? (`yes` / pick another / `propose a new one`)"

   On `yes`, go to step 4.

3. **If none fits, propose one.** Call `codefactory_deployment_profile_suggest` with the `workspaceId` and the item's `specDocumentId` (use `contextText` instead for a ticket- or known-issue-origin item, which has no spec). Nothing is persisted. Show the user the proposed name, the stack by category, the delivery surfaces and the target — and mention anything in `rejectedByPalette`, since that is the difference between what was designed and what would be saved. Ask for explicit acceptance:

   > "No existing profile fits. Proposed: **`<name>`** — `<stack by category>`, delivering `<surfaces>`, target `<targetId>`. `<rationale.profile>` Create it? (`yes` / adjust / skip)"

   On `yes`, call `codefactory_deployment_profile_create` with the suggestion's `selections`, `surfaceMappings` and `targetId` passed through unchanged. On "adjust", re-run `suggest` with `currentSelections` set to the corrected picks rather than hand-editing the payload. On "skip", say plainly in the plan that the work has no recorded stack and the picker is choosing one ad hoc — do not bury it.

4. **Attach it.** Call `codefactory_queue_set_deployment_profile` with `{ workspaceId, itemId, deploymentProfileId, rationale }`. Write `rationale` as one sentence naming the surface and why the stack matches — it is what the PM reads if this becomes a decision. Then **re-fetch the starter kit** (Step 5) so `CLAUDE.md` re-renders with the stack, and plan from the new kit.

5. **Report what happened to the workspace default.** `codefactory_queue_set_deployment_profile` also applies the default policy, and the two branches are not the same thing. Read `defaultAdoption.outcome` and say which:

   - `adopted` — the workspace had **no** default, so this profile is now it. Future specs and queue items in this workspace generate against it. Tell the user; this is a real change beyond the item in hand.
   - `proposed` — the workspace already defaults to a **different** profile, so it was **not** changed. The switch is now a PM decision on a WORK STREAM card. This item still builds against the profile you attached either way. Say both halves — a user told only "a card was raised" will think the item is blocked, and it isn't.
   - `proposal_pending` — the same switch is already waiting on a PM. Nothing new was raised.
   - `already_default` — the profile you attached was already the workspace default. Nothing changed.
   - `skipped` — the profile didn't resolve; report it and re-list.

   `defaultAdoption.message` is written to be shown verbatim if you'd rather not paraphrase.

Do **not** wait for a `proposed` decision. Like the Step 10 approval gate, it is asynchronous and belongs to the PM; the plan continues without it.

### Rework rounds

An item sent back already has a profile in nearly every case — check `deploymentProfile` anyway, but if the previous round built against a profile, keep it. Changing the stack mid-rework is not a revision, it is a restart, and Step 6.5's rule against re-planning accepted work applies to the stack too. If a requested modification explicitly asks for a different stack, treat that as the user's instruction and run the ladder above.

## Step 6 — Load assets into context

Treat each `bundle.files[i].content` value as the in-session contents for that filename when reasoning about the work:

- **`CLAUDE.md`** → project guidance, tech stack, file-size guidance, deployment-mode-specific instructions. This is your primary rulebook for the plan.
- **`SPEC.md`** → the actual spec the work item points at (the *what*).
- **`BUILD_PLAN.md`** → existing build-plan skeleton. Use as input and refine; do not start from scratch when this exists.
- **`prompt.md`** → an LLM-friendly rendering of the same spec for cross-reference.
- **`skills/<name>/SKILL.md`** (when present) → the **codified workflows** of this codebase: repeated procedures the team performs over and over, each with steps that are easy to miss. `CLAUDE.md` carries a "Codified Workflows" section naming the ones that exist. When your plan touches a workflow's trigger, open that SKILL.md and follow every step — especially the ones marked **registration**, which are files nothing in the code you are editing will lead you to (a DI module, an enum, a markdown registry). Do not reconstruct the ceremony from the nearest example; that is the failure these files exist to prevent.

Do not paste these files into chat in full unless the user asks — they're context, not output.

## Step 6.5 — If this is rework, plan the REVISION (not the implementation)

Trigger when Step 4's response carried a `rework` block, or when the starter kit contains a `REWORK.md`. Skip entirely on a first pass.

The item already has a delivered pull request. The PM did not throw it away — they asked for changes. Your job is the delta, and nothing else.

1. **Read `REWORK.md` first**, before `BUILD_PLAN.md`. It carries the round number, the PM's reason, the requested modifications as a checklist, the PR URL, the branch, and every earlier round.
2. **Check out the existing branch** named in `rework.branch` (resolve it from the PR URL if the field is absent). Do **not** create a new branch and do **not** open a second pull request — a second PR for one queue item splits the review and orphans whichever one loses.
3. **Read the existing diff** on that branch before planning. Most of the work is already there and was not objected to; re-deriving it wastes a round and risks reverting accepted decisions.
4. **Scope the plan to the send-back only.** Every item in the plan must trace to the `reason` or to one of the `modifications`. If you believe a requested modification is wrong or infeasible, say so in the plan and let the user decide — do not silently skip it, because the PM will look for it on re-submission.
5. **Check `history` for repeats.** A modification that appears in more than one round was not resolved by the previous revision. Start there, and say in the plan why the previous attempt missed it.
6. **Push to the same branch**, then go to Step 10. The re-submission's `summary` must state, point by point, how each requested modification was addressed.

Present the revision plan in the same shape as Step 8, with one extra section at the top:

```
**Rework round <n> — what the PM asked for**
- **Reason:** <verbatim from the rework block>
- **Requested modifications:** <the checklist; "[none listed — reason only]" if empty>
- **Branch being revised:** <branch> (PR <url>)
- **Repeat from an earlier round:** <which items, or "[none]">
```

## Step 7 — Show the spec TL;DR

Before drafting the plan, surface a short orientation so the picker knows what they just claimed without scrolling through SPEC.md. Render in this exact shape:

```
**Spec TL;DR — <work item name or spec title>**
- **Goal:** <1 sentence — what this work item is trying to accomplish, distilled from SPEC.md>
- **Deployment mode:** `<augment_existing | new_surface>` — <1 phrase on what that implies>
- **Scope:** <1 sentence covering the main user-visible change or capability>
- **Key acceptance criteria:** <2–4 bullet fragments lifted from SPEC.md's acceptance criteria; "[none stated]" if absent>
- **Notable constraints / risks:** <1–3 fragments — performance, security, integrations, [Needs Input] gaps; "[none flagged]" if absent>
- **Deployment profile:** <name — stackSummary, from Step 5.5; "[none — stack chosen ad hoc]" when the user skipped resolving one>
- **Picker notes:** <verbatim `notes` field from the work item; omit the line if empty>
```

**▸ Train — lead with the train, then one line per member.** Replace the block above with:

```
**Train TL;DR — <train name>** (`<trainId>`)
- **Members:** <n> — <one line per member: id, name, and its requirement in a phrase>
- **Why they travel together:** <evaluation.rationale, or the recorded overrideJustification>
- **Deployment profile:** <name — stackSummary; "[none — stack chosen ad hoc]" when unresolved>
- **Shared surface:** <files/modules more than one member touches — "[none — disjoint]" if they don't overlap>
- **Not in scope:** <unclaimedItemIds and why, or "[none]">
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
   - **Verification** — type-check / test commands, manual exercises, the acceptance criteria from the spec. When a codified workflow applied, confirm each of its registration steps landed.
   - **Out of scope** — what this plan deliberately does NOT do, so reviewers don't expect it.

   **▸ Train — three more sections, and one of them is load-bearing:**
   - **Per-member acceptance criteria**, grouped by item id, so the PM can check the PR against each item it claims to close.
   - **Ordering** — which member's change lands first where they touch shared code. Members were judged disjoint enough to share a branch, not guaranteed independent within it.
   - **Members at risk** — anything you expect may not land, so Step 10's per-item mapping is not a surprise.

   **▸ Train — keep the lease alive.** The lease is **45 minutes**, and a run that outlives it is treated as dead so its items are released rather than stranded. On a long run call `codefactory_train_claim` with `heartbeat: true` periodically. If a heartbeat returns false you no longer hold the train: stop and re-read with `codefactory_train_get` rather than writing code nobody has a claim for.

4. When plan mode IS active and a plan file path was provided, write the plan there. Otherwise post the plan in chat.

## Step 9 — Hand off for implementation

When the plan is ready, tell the user:

> "Plan drafted for **`<spec title>`** (queue item `<itemId>`). Review it; on approval, the picker (you or a follow-up agent) executes the plan, pushes the work as a pull request, and then comes back here so I can submit it for PM approval via `codefactory_queue_submit_for_approval`. Once it's submitted, this item is off our plate — the PM approves and merges it in PMCollab, or sends it back to the queue with their reasons. If you'd rather drop the work back to the pool now, the picker can release it via `codefactory_queue_release`."

The skill does NOT auto-implement. Wait for the picker to explicitly confirm that a PR has been pushed before moving to Step 10.

## Step 9.5 — Collect the spec deltas the picker negotiated

While implementing, the picker almost always negotiates the spec against the real code: it corrects implementation detail that bled into the spec inaccurately, and it intentionally drops scope (the plan's **Out of scope** section). Those decisions must get back into the spec — but most are routine, and the PM should only see the genuine product calls.

This is no longer a separate tool call. Collect the deltas here and pass them to Step 10's single submission, so the PM gets **one** decision covering both the spec changes and the merge rather than two.

Collect each delta as one of:

- **`kind: "change"`** — an edit to an existing spec item (a behavior, rule, or acceptance criterion the code implemented differently). Set `changeType` to `modification` / `removal`, `sectionHeading` to the spec section it touches, `beforeContent` to the existing text, `afterContent` to the corrected text.
- **`kind: "out_of_scope"`** — something deliberately dropped (the plan's "intentionally dropped" list). Use `changeType: "addition"`, `sectionHeading` of the spec's Non-Goals / V1 Scope Boundary section, and put the dropped-scope note in `afterContent`.

For every delta give a one-sentence `rationale` and cite `codeProvenance` (file paths / the PR URL). If the code matches the spec exactly, pass `deltas: []`.

`codefactory_queue_propose_spec_changes` still exists and still works, but calling it separately then submitting means the reconciliation runs twice — and if the first call escalates anything, it parks the item and releases the claim, so the follow-up submit has nothing claimed to submit. Prefer the single Step 10 call.

## Step 10 — Submit for PM approval, then stop

Trigger when the user says any of:
- "PR is up: `<url>`" / "PR pushed, mark it done"
- "Submit the queue item" / "Complete the queue item with this PR"
- Replies to the Step 9 hand-off message with a GitHub / Azure DevOps pull-request URL

Required inputs at this step:
- `workspaceId` + `itemId` — carry forward from the earlier steps; do NOT re-prompt.
- `pullRequestUrl` — the URL the user just pasted. Validate that it is an `https://` URL pointing at a PR (GitHub `/pull/N`, Azure DevOps `/pullrequest/N`, etc.). If it does not look like a PR URL, ask the user to confirm before proceeding. On a **rework** round this is the SAME PR as the previous round — do not expect a new URL, and query it if you get one.
- `summary` — one paragraph: what was built, and anything the PM should weigh before approving. On a rework round, state point by point how each requested modification was addressed.
- `deltas` — from Step 9.5; `[]` when the code matches the spec.

**▸ Train — two calls, in this order, and the order matters.**

*First*, every member the run actually **delivered** goes through the same gate below: `codefactory_queue_submit_for_approval` per member, with the **same** `pullRequestUrl` (there is one PR), a `summary` scoped to *that member* — a summary describing the whole train tells the PM nothing about the item they are deciding on — and that member's own `deltas`. Never pool one member's deltas onto another's submission. A member the run did **not** deliver is not submitted: it has no deliverable, and submitting it against a PR that does not contain its work is a false claim to the PM.

*Then* `codefactory_train_submit` with `{ workspaceId, trainId, prRef, results }` — `prRef` in `org/repo#123` form, and **one `results` entry per member of the train** — including any you did not hold or that was cancelled — with a `reason` on every miss, written for whoever re-trains it: what blocked it, and what would unblock it. The server enforces the order above: it **refuses, recording nothing**, while any member mapped `delivered` is still `in_progress` (its own submission has not run), and it returns the undelivered members this run holds to the pool (`releasedItemIds`). This call is retry-safe; a repeat returns the existing result rather than opening a second PR or overwriting the mapping. Read `undelivered` and confirm what returns to the pool:

> "Train **`<name>`** submitted on `<prRef>`. `<d>` of `<n>` members delivered and are with the PM; `<u>` returned to the queue (`<ids>`) and can ride a later train. This is off our plate — what's next?"

Then stop, exactly as the single-item path does.

### Single item

Call `codefactory_queue_submit_for_approval` with `{ workspaceId, itemId, pullRequestUrl, summary, deltas }`. The backend:

1. Records the PR on the work item.
2. Runs an architect/APM triage on each delta — routine ones are auto-applied to the spec as a new version (no PM action), genuine product calls are escalated onto the same approval decision.
3. Moves the item to `pending_approval` — or, when anything escalated, to `awaiting_spec_approval`, which also **releases the claim**: the item is parked and unassigned, and the queue shows "Waiting for `<m>` spec approvals" instead of a stale assignee.
4. Posts a note on the pull request itself saying which of the two it is waiting on, so nobody merges it out from under the PM.
5. Raises the WORK STREAM card the PM acts on.

Read `status` on the response — `pending_approval` or `awaiting_spec_approval` — and say which one it is. On success, confirm and **stop**:

> "Submitted **`<spec title>`** (`<itemId>`) for PM approval on `<pullRequestUrl>`. `<n>` routine spec change(s) were auto-applied; `<m>` needed a product call and ride on the same decision. This item is off our plate — approving merges the PR and completes the queue item, and requesting rework sends it back to the queue with the PM's brief attached. What's next?"

When it parked instead:

> "**`<spec title>`** (`<itemId>`) is parked on `<m>` spec approval(s) and is now unassigned — the claim was released. Nothing moves on it until the PM decides those changes: approving updates the spec, merges `<pullRequestUrl>` and closes the item; asking for changes puts it back on the queue with their brief for whoever picks it up next. What's next?"

Do NOT poll for the outcome, do NOT call `codefactory_queue_complete`, and do NOT tell the user to wait. Offer to pick up another queue item or move on to whatever they want.

Error handling:

- `not_found` — the work item was deleted between Step 4 and now. Tell the user and stop.
- `not_in_progress` — the item was released, cancelled, or already completed. Surface the returned `currentStatus` and stop; do NOT silently re-claim. `pending_approval` is not an error — a re-submission refreshes the open gate. `awaiting_spec_approval` means an earlier call already parked it on the PM's spec decisions: report that and stop, do not re-claim it.
- `conflict` — a concurrent transition. Re-read with `codefactory_queue_list` and report the current state; do not retry blindly.

### When the PM sends it back

You will not be in the session for that. It happens the same way from either wait — a `request-rework` on the approval card, or declining any of the escalated spec changes. The item returns to `waiting_for_resources` carrying the PM's reasons and requested modifications, and the next `/pm:process-queue` run picks it up as rework (Step 4 → Step 6.5). That next run may well be you, in a later session — the `rework` block is the whole hand-off, so nothing needs to be remembered across sessions.

### Completing without the gate

`codefactory_queue_complete` with `override: true` completes an item outright — no approval, no merge, and any escalated spec changes abandoned. It exists for the case where the PR was already merged by hand. Use it only when the user explicitly asks for it, and say what it skips.

## Out of scope

- Running the in-app code-gen pipeline (the one that produces a full `CodeFactoryArtifact` with generated files).
- Implementing the spec for the user — the picker drives the implementation; this skill plans and books the hand-off.
- Calling `codefactory_queue_release` from this skill.
- Submitting without a PR URL the user has explicitly provided.
- **Waiting on, polling for, or reporting the PM's approval decision.** The gate is asynchronous by design; the session ends at submission.
- **Waiting on a `deployment_profile_default` decision.** Same shape: raised in Step 5.5, decided by the PM later, never blocking the plan.
- Editing or deleting an existing deployment profile, or changing which profile other work items are filed under — Step 5.5 creates and attaches, it never rewrites what is already there.
- Approving or merging on the PM's behalf — the whole point of the gate is that a human decides.
- Running the in-app Code Factory agent lane, which runs trains by its own path with its own preflight — this skill is the human/Claude Code picker's route.
- **Dissolving a train on your own initiative, or editing a committed train's membership.** A train that will never run MUST be dissolved or its members stay locked. When the user asks for that, call `codefactory_train_dissolve` with `{ workspaceId, trainId }` (workspace admins only): it releases every member to individual pickup and refuses a submitted train or one whose run holds a live lease. Membership cannot be edited in place — dissolve, then compose the new grouping.
- Forming a train the user has not agreed to, or forming one as a side effect of looking for work.
