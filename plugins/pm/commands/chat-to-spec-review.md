---
description: Convert the current Claude chat into a PMCollab spec and open a Spec Review with Sphinx / Phoenix / Chimera.
---

# /pm:chat-to-spec-review

Take the current conversation, format it into a unified PMCollab spec (NEW_SYSTEM, MODIFICATION, or CHANGE_SPEC), upload it to the chosen workspace, and open a Spec Review session so stakeholders can critique it in chat. Optionally, when the discussion clearly defines a capability, also create the Capability and its Behaviors under the chosen Use Case.

**Routing note:** this command and `/pm:quick-change` produce the same CHANGE_SPEC artifact — the difference is whether review gates the code or trails it. Use this command when the conversation itself carries design thinking worth harvesting into the spec, or the change exceeds quick-change's scope ceiling (>~5 files, multiple use cases, spec-linked surfaces, no promoted baseline). Use `/pm:quick-change` when the user just wants a small, well-scoped edit made and the spec captured behind it.

## Hard rules

- **Never invent IDs.** Workspace, use case, capability, and chat IDs all come from MCP tool responses. If a step needs an ID you don't have, call the discovery tool first.
- **Confirm before destructive or visible-to-others steps.** That includes creating the spec document, starting the review (others may get notified), and creating a capability.
- **One spec per invocation.** Don't try to bulk-create multiple specs in one run.
- **Stop on maturity gate failure.** If `spec_review_start` returns "Spec Review not available at current maturity stage," surface the message verbatim and stop — don't auto-bump maturity.
- **Don't fabricate; mark gaps honestly (see Step 3).** Draft from chat context first, inferring where reasonable. Where you inferred a value rather than seeing it stated, prefix the line `[Proposed — needs validation]`. Reserve `[Needs Input]` for *non-required* sections the user explicitly skips — never leave a required section (for CHANGE_SPEC, sections 16 Migration & Compatibility / 17 Affected Test Surface) as `[Needs Input]`. Reviewers will flag whatever remains.

## Step 1 — Classify the spec type

Read the conversation. Decide:

| Signal | Spec type |
|--------|-----------|
| User describes a brand-new product / system / tool | `NEW_SYSTEM` |
| User describes a major revision / re-architecture of an existing thing | `MODIFICATION` |
| User describes a delta — adding a feature, tweaking behavior, fixing a bug — against an existing baseline spec | `CHANGE_SPEC` |

If ambiguous, ask once:

> "I can package this as a NEW_SYSTEM (whole new product), MODIFICATION (major redesign), or CHANGE_SPEC (delta against an existing spec). Which fits?"

**This is a preliminary classification.** If you land on `MODIFICATION` or `CHANGE_SPEC`, the real CHANGE_SPEC-vs-MODIFICATION call is made in Step 2.5 — once the use case is picked and its `currentSpec` is known. NEW_SYSTEM is the only verdict you can finalize here without loading use case context.

## Step 2 — Pick workspace and (optional) use case

Delegate selection to the sibling commands — do not duplicate their logic here.

1. Run the `/pm:select-workspace` flow (see `commands/select-workspace.md`) to resolve:
   - `workspaceId` + `workspaceTitle` (required)
   - `userId` / `email` / `createdByName` — cached identity reused in Steps 4–6

2. Run the `/pm:select-usecase` flow (see `commands/select-usecase.md`), passing:
   - The `workspaceId` from step 1 (required).
   - An `intentKeywords` string derived from the current conversation when the workspace has many use cases — pulls things like the topic, feature name, or domain noun from the chat so the picker can pre-filter the list. Skip if the conversation is too generic to extract a useful keyword.

   It returns `useCaseId` + `useCaseTitle` (both undefined when the user chose "none / leave unscoped" — that's fine, the spec proceeds workspace-wide).

If the user later signals "use a different workspace" or "switch use case," re-run the appropriate picker rather than asking ad-hoc.

## Step 2.5 — Resolve baseline from use case context

If a `useCaseId` was returned from Step 2, you MUST resolve whether a promoted baseline spec already exists before drafting. Otherwise you risk authoring a fresh DESIGN_SPEC on top of a use case whose CurrentSpec the workspace already considers canonical — which is exactly what produces the "MODIFICATION instead of CHANGE_SPEC" mistake.

1. Run the `/pm:load-usecase-context` flow (see `commands/load-usecase-context.md`) or call `usecase_load_context` directly with `{workspaceId, useCaseId}`. The returned pack's `currentSpec` field carries the promoted-baseline state.

2. Read `currentSpec`:
   - **`currentSpec === null`** → the use case has not been promoted. The CHANGE_SPEC path is not available against this use case. Your spec type is now locked to `NEW_SYSTEM` (no baseline anywhere) or `MODIFICATION` (existing thing, no promoted spec yet) per Step 1.
   - **`currentSpec` is non-null** → a baseline exists. Lock the spec type to `CHANGE_SPEC` and use `currentSpec.baselineSpecDocumentId` as the `baselineSpecDocumentId` you'll pass to `spec_document_create` in Step 4. It resolves on both `source` values, so `source === 'creation-spec'` (promoted, no change spec applied yet) is not a reason to go looking for one. Do NOT downgrade to `MODIFICATION` just because the conversation describes a substantial expansion — material-but-incremental work against a promoted baseline is exactly what CHANGE_SPEC is for; CHANGE_SPEC is not size-gated.
   - **`currentSpec` is non-null but `baselineSpecDocumentId` is null** (promoted, but no promoted design spec backs its record) → still CHANGE_SPEC. Call `spec_document_list_by_usecase(workspaceId, useCaseId)` to get the candidate set, filter to `specType: 'design'` + `status = 'promoted'` — the stored `specType` is `design` or `change`, never the `NEW_SYSTEM` / `MODIFICATION` classification labels — and ask the user to pick one as the baseline. Mention how many were hidden by the filter so the user can opt into a wider view.
   - **Never pass `currentSpec.baseCreationSpecId`.** It is a CreationSpec id (`cspec_…`) in a different id space from `SpecDocument.id` (`spec_…`); nothing validates it, so the change spec is created pointing at a document that does not exist and promotion then computes no CurrentSpec at all. It is lineage only.

If the user later asks "use a different baseline" at any point in the flow, call `spec_document_list_by_usecase` with the same filter and let them pick — never invent a baseline id.

3. If the user picked "none" for the use case in Step 2, skip this step — there's no per-use-case baseline to resolve and the Step 1 classification stands.

This step is read-only. If the load fails, surface the error rather than silently falling back to MODIFICATION.

## Step 3 — Fetch the schema and draft the markdown interactively

Call the `get_spec_schema` MCP tool to fetch the canonical structure for the spec type you classified in Step 1:

- `specType: 'DESIGN_SPEC'` for `NEW_SYSTEM` and `MODIFICATION`.
- `specType: 'CHANGE_SPEC'` for `CHANGE_SPEC`.

Parse the returned JSON Schema. It is the single source of truth for the document structure — do not author from memory, do not improvise section numbering. The schema documents:

- Which top-level fields exist (`changeHeader`, `changeProposal`, `sectionDeltas`, `readinessChecklist` for change specs; the analogous fields for design specs).
- Which sections live under `sectionDeltas.properties` — keys `1`…`23` are the design spec's own section numbers (a change spec numbers each delta section by the design section it modifies), with the canonical heading in each property's `title`.
- Which sections are `required`. For CHANGE_SPEC the mandatory ones are `16` (Migration & Compatibility) and `17` (Affected Test Surface) — always emit these, even for trivial changes ("No migration required." / a one-line regression note are fine; `[Needs Input]` is not).

**Drafting is interactive, not silent.** Don't just emit a markdown blob with `[Needs Input]` placeholders scattered across required sections. Walk the schema section-by-section:

1. **Propose, don't just ask.** For each section the schema lists, draft your best-effort content from the conversation context first — quote what the user said, infer the rest where reasonable — then present the proposal to the user as `"Section N — <title>: <proposed text>. Looks right? (yes / edit / skip)"`. Drafting from chat context first beats peppering the user with cold-start questions.
2. **Ask focused follow-ups for thin areas.** When the conversation doesn't supply enough signal for a section, ask one targeted question rather than handing back a placeholder. E.g. "I don't have a clear answer for permissions — who can do this, and who can't?"
3. **Mark inferences explicitly.** Where you inferred a value from context rather than seeing it stated, prefix the line with `[Proposed — needs validation]` so the user knows to scrutinize it.
4. **Only use `[Needs Input]` for non-required sections** where the user explicitly says "skip" or "I don't know yet." For required sections (16 / 17 in CHANGE_SPEC) push back once and get a real answer.

Draft the markdown so the body conforms to the schema:

- Use the schema's section numbers and canonical titles in the `## N. Title` heading form (e.g. `## 16. Migration & Compatibility`), not section numbers from prior conversations or other templates. Change Header, Change Proposal, Change Summary Table and Readiness Checklist are named, unnumbered `##` parts.
- For CHANGE_SPEC bodies, put your section edits under a `## Section Deltas` heading and use `Add:` / `Change:` / `Remove:` blocks inside each subsection. The `extractSectionDeltas` parser (see `backend/src/data/changeSpecHelpers.ts`) keys on those verbs to auto-build the Change Summary Table on save — do NOT hand-author the table.
- Cite evidence from the chat where you can ("user said: …").
- Open the body with `# Spec: <Title>` (DESIGN_SPEC) or `# Change Specification: <Title>` (CHANGE_SPEC). Include a Change Header / Change Proposal area for change specs that cites the WHY of the change.

## Step 3.5 — Pre-flight readiness gate

Before persisting anything, run a readiness pre-flight against the draft so the user sees what's still missing.

1. **Create the idea-chat session early** via `ideachat_create_session` — pass `title`, `description` summarising the conversation, `goalType`, `specLevel: 'design_spec'`, `maturityStage: 'shaping'`, `createdBy`, `createdByName`, and **`useCaseId` if Step 2 resolved one** (omit when the user chose "none / leave unscoped"). Three notes:
   - `useCaseId` is what the workspace UI reads to show the use-case context badge on the chat and what `spec_readiness_eval` / `spec_review_start` consume to pull capability/persona/spec context — skip it and the chat is created unscoped and the review session shows up without a use-case link.
   - `maturityStage: 'shaping'` is required so the **Design Spec** action on the workspace UI is unlocked the moment the user lands on the chat. The default `'spark'` keeps that action gated for the brainstorming phase — but we've already drafted a full spec by Step 3, so we're past brainstorming and the user expects to be able to open the spec immediately.
   - Capture the returned `id` as `chatId`. Creating the chat first is what gives the readiness eval something to chew on.
2. **Seed the chat** via `ideachat_send_message`: post one or two messages that summarise the gathered conversation + the drafted spec content so the eval has context. Mark them as agent-authored (`senderRole: 'agent'`). This is throwaway content from the eval's perspective — it just needs to exist for the dimension scoring to run.
3. **Call `spec_readiness_eval`** with `{workspaceId, chatId, evaluatedBy: <userId>, useCaseId?}`. This is the dry-run sibling of `spec_readiness_review` — same engine, no SpecEvaluation row persisted. The tool returns `{readiness: {allResolved, dimensions[]}, todoItems[], openQuestions[]}`.
4. **Present the todo list to the user.** For each `todoItems[i]` with `status === 'pending'`, surface the dimension label and the `question`. Then ask: `"Resolve these? (resolve all / pick one / bypass)"`.
   - On `resolve all` or `pick one`: walk through each pending todo as an interactive Q&A. Update the draft markdown as the user answers. Re-call `spec_readiness_eval` to refresh the verdict (no Cosmos pollution — dry-run is free).
   - On `bypass`: skip the gate. State clearly: `"Bypassing readiness gate — <N> dimensions still pending. The Spec Review in Step 5 will flag them."` and proceed.
5. **Don't loop forever.** If a re-eval after Q&A still shows pending items the user can't answer, stop the loop after 2 rounds and offer `bypass` rather than circling.

`spec_readiness_eval` does NOT persist a SpecEvaluation row, so re-calling it as the user resolves todos is cheap. Only when the spec is actually promoted (Step 5's `spec_review_start` triggers the real `spec_readiness_review` internally) does an audit row get written.

## Step 4 — Create the spec document

The idea-chat session was already created in Step 3.5 to power the readiness gate. Now just persist the spec doc against it.

Confirm with the user before any writes:

> "Ready to create the spec doc in workspace `<workspace title>` (chat id `<chatId>`). Proceed?"

On approval:

1. **Create the spec document** with `spec_document_create`:
   - `workspaceId`, `name` (same as chat title), `specType`, `chatId` (from Step 3.5), `useCaseId` (if chosen)
   - `initialMarkdown`: the full drafted markdown from Step 3 (enriched by any todo answers from Step 3.5).
   - For CHANGE_SPEC: also pass `baselineSpecDocumentId` — the value resolved in Step 2.5 (`currentSpec.baselineSpecDocumentId` from `usecase_load_context`, or the spec the user picked via `spec_document_list_by_usecase` when that was null). Never invent this id, and never substitute `baseCreationSpecId`; if Step 2.5's resolution determined no baseline exists, the spec was locked to NEW_SYSTEM / MODIFICATION and `baselineSpecDocumentId` is omitted.
   - `createdBy`, `createdByName`.

   Capture the returned `document.id` as `specDocId`.

2. **For CHANGE_SPEC only** — immediately follow with `spec_document_update`, passing `docId = specDocId` and `currentMarkdown` = the same drafted markdown. `spec_document_create` does NOT auto-generate the Change Summary Table or run validation; the update path routes through `saveDraft` which:
   - Replaces any hand-written table with the auto-built 5-column version derived from your `Add:`/`Change:`/`Remove:` deltas.
   - Runs `validateChangeSpec` and returns `{errors, warnings}`.

   Surface any returned errors and warnings to the user verbatim before continuing to Step 5 — they identify exactly what needs fixing in the Spec Manager.

   If the user wants to amend the markdown later in this run, repeat the `spec_document_update` call.

## Step 5 — Start the Spec Review

Call `spec_review_start`:
- `workspaceId`, `chatId`, `title`, `createdBy`
- `maturityStage`: `'shaping'` (the minimum to pass the gate; the chat session you just created starts at `'spark'`, so you must override).
- `useCaseId` if relevant.
- `conversationSummary`: the same summary used as the chat description.

If it returns an error containing "not available at current maturity stage," surface that verbatim and stop. Otherwise, return the `deepLink` to the user:

> "Spec review round 1 is live. Open it: `<deepLink>` — Sphinx, Phoenix, and Chimera will post their critiques in the chat."

## Step 6 — Optional: create a Capability + Behaviors

Only if the conversation clearly defines a capability with concrete behaviors. Otherwise skip silently.

Surface for confirmation:

> "I noticed this conversation defines a capability: **Auto-tag time entries**. Should I create it under the chosen use case with these 3 behaviors?
> - [Scenario] On focus change, infer a project tag from window title.
> - [Permission] User can override the tag within 24h.
> - [Edge Case] If no project matches, leave entry untagged.
> Yes / No / Adjust"

On `Yes`, call `capability_create` with:
- `workspaceId`, `useCaseId`, `createdBy`, `createdByName`
- `whatBusinessMustDo`, `whyItMatters`, `inputsOutputs`, `painPoints`, `stakeholders`, `opportunities` — short paragraphs from the chat.
- `behaviors`: array of `{ content, group, source: 'Conversation' }`. Valid `group` values: `RequirementSet`, `Scenario`, `Permission`, `UI Requirement`, `Data Requirement`, `Workflow`, `Edge Case`, `Integration`, `Constraint`, `Decisions`, `Other`.

Report the resulting capability ID and behavior count.

## Step 7 — Final summary

Print a compact recap:
- Workspace + (use case if any)
- Spec type + spec document ID
- Idea Chat ID
- Spec Review document ID + round number
- Capability ID + behavior count (if created)
- Deep link to the Spec Review

## Out of scope

Don't do any of these in this command:

- Whiteboards, UseCase-card creation, or ProductContext edits beyond the chosen `useCaseId` link.
- Editing the spec markdown after the review starts (the user does that in the Spec Review modal or via `@specky` in the chat).
- Re-runs / scheduled reviews.
- Bulk-creating multiple specs.
