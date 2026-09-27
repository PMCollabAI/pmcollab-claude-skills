---
description: Reconcile spec-vs-code drift for one PMCollab use case end-to-end (load spec + code contexts + live files, propose per-finding actions).
---

# /pm:spec-align

Reconcile drift between a use case's PMCollab spec and the code that implements it. The command is read-then-decide-then-confirm: load both sides + the live files, propose per-finding actions, ask the user, then execute.

## Hard rules

- **One use case per invocation.** Do not loop over multiple use cases — repeat the command instead.
- **Read both context packs before reasoning.** Do not propose actions from spec alone or code alone.
- **Read the live local files.** The code-context pack contains extracted facts captured at scan time, not current bytes. Use the local `Read` tool on every file in `codeContext.files[].path` to see what's actually there now.
- **Confirm before every visible action.** File edits and change-spec creation are both visible to others. Confirm per-finding, not in bulk — the user may approve one and reject another.
- **Never invent file paths or rule IDs.** Only act on what the packs and live `Read` calls return.
- **Stop cleanly when there's no scan.** If `codeContext.scan === null`, surface the message and exit — do not fabricate a comparison.

## Step 1 — Resolve the use case

If `workspaceId` and `useCaseId` aren't already set in the session, run `/pm:select-usecase` (see `commands/select-usecase.md`; auto-chains to `/pm:select-workspace`).

## Step 2 — Load the spec context

Run `/pm:load-usecase-context` (see `commands/load-usecase-context.md`) with the resolved `{workspaceId, useCaseId}`. Capture the returned pack as `specContext`.

If `specContext.currentSpec === null`, the use case has not been promoted yet — stop and tell the user "this use case has no promoted spec; nothing to align against. Promote the spec first or run `/pm:chat-to-spec-review` to author one."

## Step 3 — Load the code context

Run `/pm:load-code-context` (see `commands/load-code-context.md`) with the same `{workspaceId, useCaseId}`. Capture the returned pack as `codeContext`.

If `codeContext.scan === null`, stop and tell the user "no completed code scan found for this workspace; run a scan in PMCollab first, then retry."

## Step 4 — Read the live repo files

For each entry in `codeContext.files`, call the local `Read` tool on the path. If a file is missing in the working tree, mark it as `[DELETED LOCALLY]` in the findings rather than skipping silently — a deleted file IS a drift signal.

If many files don't resolve, the user is likely running outside the relevant repo's working directory. Stop and ask:

> "Several files from the code context don't exist in the current working directory. Are you in the right repo checkout? (`<paths…>`)"

## Step 5 — Identify drift findings

Compare the three sources side-by-side, walking each section of `specContext.currentSpec.markdown` against the matching extracted facts and live file content. Look for:

- **Behavior-level drift** — a behavior listed under a capability in the spec but not visible in any extracted business rule or live file path under that capability's components.
- **Business-rule drift** — an `extractedBusinessRules[]` entry whose `name` or `description` doesn't appear in the spec's behaviors / acceptance criteria, OR a spec rule with no matching extracted rule.
- **AI-prompt drift** — an `extractedAIPrompts[]` row whose `promptText` (or `associatedCapabilityName`) contradicts what the spec says the agent should do.
- **MCP / A2A surface drift** — endpoints declared in the spec but absent from `extractedMcpEndpoints[]` / `extractedA2AEndpoints[]`, or vice versa.
- **Recent breaking change** — `codeContext.changeLog[]` entries with `breakingChange: true` or `customerVisible: true` that the spec hasn't been updated to reflect.
- **Live-vs-extracted drift** — when the live `Read` of a file shows behavior the extracted-facts pack doesn't reflect (the scan is stale on this file).

For each finding, classify the recommended action:

- **Modify code** — when the spec is the source of truth (e.g. an explicit decision in `specContext.currentSpec.markdown`, an approved CHANGE_SPEC in `appliedChangeSpecIds[]`, or the use case's stated intent in `specContext.useCase.details`).
- **Draft CHANGE_SPEC** — when the live code is the source of truth (e.g. a recent `changeLog[]` entry with `customerVisible: true` and no matching spec update, or a deliberate code direction the spec predates).
- **Investigate** — when the right answer isn't clear from the data alone.

## Step 6 — Surface the findings

Render a numbered list:

```
Drift findings for "<useCase title>" (spec v<currentSpec.version>):

1. [Modify code] src/services/timeTrackingService.ts
   Spec §4.2 says "auto-tag must respect a 24h override window."
   Live code: no override check; extracted business rule `tag-must-match-project` makes no mention of the window.
   Suggested fix: add override-window check around the tag-set in inferProjectTag().

2. [Draft CHANGE_SPEC] src/routes/time.ts
   Live code adds POST /time/bulk-import; extracted change-log entry `cl-1` flags it as customer-visible breaking change.
   Spec has no bulk-import flow.
   Suggested change spec: §3 add bulk-import use-case flow; §6 add new acceptance criteria.

3. [Investigate] src/services/timeTrackingService.ts
   Extracted AI prompt `prompt-1` says "infer tag from window title"; spec §3.1 says "infer from active calendar event."
   Both behaviors exist in the live file. Which is canonical?
```

For each finding, ask:

> "1) Apply suggested fix? (yes / skip / change action / discuss)
>  2) Apply suggested fix? (yes / skip / change action / discuss)
>  3) Investigate first — what would you like to know?"

Wait for the user's choices.

## Step 7 — Execute approved actions, one at a time

For each `yes`:

- **Modify code path:** edit the named file using the local `Edit` (preferred) or `Write` tool. Show the diff in chat. Do not commit — leave the changes staged for the user.
- **Draft CHANGE_SPEC path:** the change-spec body MUST conform to PMCollab's canonical schema. Do this in order:
  1. Call the `get_spec_schema` MCP tool with `specType: 'CHANGE_SPEC'` to fetch the authoritative schema as JSON. Parse it. This is the single source of truth for which sections exist and which are mandatory — do not author from memory.
  2. Draft the change-spec markdown so the body conforms to the schema:
     - Open with `# Change Specification: <Title>`.
     - Emit one `## N. <title>` section per baseline section your finding touches, between the Change Summary Table and the Readiness Checklist. Section numbers + titles come from the schema's `sectionDeltas.properties` (keys `1`…`23` are the design spec's own section numbers; each property's `title` is the canonical heading).
     - The schema lists `16` (Migration & Compatibility) and `17` (Affected Test Surface) as `required` — emit `## 16. Migration & Compatibility` and `## 17. Affected Test Surface` on every change spec, even for trivial drift. For trivial cases write "No migration required." and a one-line regression test note rather than `[Needs Input]`.
     - Inside each subsection use `Add:` / `Change:` / `Remove:` blocks. The system's `extractSectionDeltas` parser keys on these verbs to build the auto-generated Change Summary Table — see `backend/src/data/changeSpecHelpers.ts` for the exact grammar.
     - Cite the drift signal that drove the change in a `## Change Proposal` (or equivalent) section near the top: the extracted business rule id, change-log entry id, or file path. Reviewers need WHY, not just WHAT.
  3. Call `spec_document_create` with:
     - `specType: 'CHANGE_SPEC'`
     - `workspaceId`, `useCaseId`
     - `baselineSpecDocumentId`: `specContext.currentSpec.baselineSpecDocumentId` from the loaded pack — NOT `baseCreationSpecId`, which is a CreationSpec id in a different id space and leaves the change spec pointing at a document that does not exist. When it is null, resolve a baseline with `spec_document_list_by_usecase` (filter `specType: 'design'` + `status: 'promoted'`) instead of guessing.
     - `name`: a verb-led title derived from the finding (e.g. "Update Section 9 to reflect bulk-import endpoint")
     - `initialMarkdown`: the drafted body
     - `createdBy` / `createdByName`: from the cached identity (`/pm:select-workspace` provides these)
     - Confirm with the user one more time before this call — change-spec creation notifies others.
  4. Immediately call `spec_document_update` with `docId` = the returned id and `currentMarkdown` = the same drafted body. This routes through `saveDraft`, which auto-generates the Change Summary Table from your `Add:`/`Change:`/`Remove:` blocks and runs `validateChangeSpec`. Surface any returned errors / warnings verbatim — they tell the user what to fix in the Spec Manager.

For each `change action`, swap the recommended action and re-confirm.
For each `skip`, record it in the recap so the user can revisit later.
For each `discuss`, walk through the relevant excerpts of spec / extracted facts / live file, then re-prompt for a decision.

## Step 8 — Final recap

Print:

- Findings: total / applied (modify-code) / drafted (change-spec) / skipped / under-discussion.
- For each applied: file path + diff summary.
- For each drafted: change-spec id + title + a "open this in PMCollab" hint.
- For each skipped: short reason.

## Out of scope

- Multi-use-case alignment in one invocation.
- Authoring a brand-new spec (use `/pm:chat-to-spec-review`).
- Promoting a drafted CHANGE_SPEC to applied (regular Spec Manager flow).
- Running the scan itself.
- Committing or pushing the file edits — leave the working tree dirty so the user reviews before commit.
