---
description: Express path — make the requested code change immediately, then capture it as a PMCollab CHANGE_SPEC from the diff (reviewers run async, commit stamped with a Change-Spec trailer).
---

# /pm:quick-change

Make the requested code change first, capture the change spec behind it. The process is a receipt, not a gate: the user gets their edit at coding-agent speed, and PMCollab gets a CHANGE_SPEC linked to the diff without the user filling anything out. Reviewer agents (Sphinx / Phoenix / Chimera) critique the captured spec asynchronously — they never block the edit.

## Routing — quick-change vs chat-to-spec-review

Both flows produce the same CHANGE_SPEC artifact and lifecycle. The only difference is whether review gates the code or trails it. Pick by what's in front of you:

| Signal | Route |
|--------|-------|
| Thin context — a sentence or two of request, small diff, one component | **quick-change** (this command) |
| Rich preceding conversation — the design thinking in this chat is itself worth harvesting | `/pm:chat-to-spec-review` |
| Net-new capability / new system, not a delta on something promoted | `/pm:chat-to-usecase` or `/pm:chat-to-spec-review` |
| The user explicitly names either flow | What they named |

Announce the route in one line and let the user override.

## Scope ceiling — when to escalate mid-flight

Escalate to `/pm:chat-to-spec-review` — carrying over everything drafted so far, never restarting — when any of these turns out to be true:

- The edit would span **more than ~5 files** or cross **multiple use cases**.
- The use-case context shows the touched behaviors/entities are **load-bearing for other specs** (e.g. `appliedChangeSpecIds[]` or capabilities referenced elsewhere), so the change deserves review *before* merge.
- The use case has **no promoted baseline** (`currentSpec === null`) — CHANGE_SPEC needs a baseline; the full flow handles NEW_SYSTEM / MODIFICATION classification.
- While editing, you discover the "small fix" actually requires a design decision the user hasn't made.

## Hard rules

- **Edit first.** Do not make the user answer spec questions before the code change lands. Capture happens after the edit is verified.
- **Never invent IDs.** Workspace, use case, chat, spec, and baseline IDs all come from MCP tool responses.
- **One confirmation, total.** The single confirm covers the persist bundle (idea-chat session + spec document + review start). Everything before it runs without questions; everything after it reports, not asks.
- **Never skip capture silently.** If the user declines capture, say plainly that the change is uncaptured and will surface as drift. If capture *fails*, surface the error and report the trailer step as skipped — do not pretend it happened.
- **Verify the edit per repo convention** (typecheck, targeted tests) before capturing — the spec should describe a change that works.
- **Don't fabricate spec content.** Draft from the actual diff and the request. Prefix inferred lines with `[Proposed — needs validation]`. Required sections (16 Migration & Compatibility / 17 Affected Test Surface) always get real content — for trivial changes "No migration required." and a one-line regression note are fine.

## Step 1 — Make the edit

Do the requested change the way you normally would: find the code, make the edit, run the repo's typecheck/tests for the touched area. If the user's request is ambiguous about *what* to change, resolve that ambiguity now (it blocks the edit, not the process).

While editing, keep a running note of: files touched, behavior before → after, and any inference you made. This becomes the spec draft in Step 4.

Check the scope ceiling as the diff takes shape — escalate early rather than after the fact.

## Step 2 — Resolve workspace + use case (minimal friction)

1. Run the `/pm:select-workspace` flow (see `commands/select-workspace.md`). If a workspace is already resolved in this session, reuse it silently.
2. Run the `/pm:select-usecase` flow (see `commands/select-usecase.md`) with `intentKeywords` derived from the changed files / feature area. When exactly one use case plausibly matches, state the match and proceed — don't force a menu. Ask only when genuinely ambiguous.

## Step 3 — Resolve the baseline

Call `usecase_load_context` with `{workspaceId, useCaseId}` and read `currentSpec`:

- **`currentSpec` non-null with a `baselineSpecDocumentId`** → that is the baseline. Pass it straight to `spec_document_create`. It resolves on both `source` values — `creation-spec` (promoted, no change spec applied yet) is the normal state, not a degraded one, so do not treat it as a reason to go looking.
- **`currentSpec` non-null with `baselineSpecDocumentId: null`** → the use case is promoted but no promoted design spec backs its record. Call `spec_document_list_by_usecase`, filter to `specType: 'design'` + `status: 'promoted'`, and pick the obvious baseline; ask only if more than one candidate remains.
- **`currentSpec === null`** → scope-ceiling escalation (see above): no baseline means no CHANGE_SPEC; hand off to `/pm:chat-to-spec-review`.

Never pass `currentSpec.baseCreationSpecId` as a `baselineSpecDocumentId`. It is a CreationSpec id (`cspec_…`) in a different id space from `SpecDocument.id` (`spec_…`); nothing validates it, so the change spec is created pointing at a document that does not exist and promotion then computes no CurrentSpec at all. It is lineage only.

## Step 4 — Draft the change spec from the diff

Call `get_spec_schema` with `specType: 'CHANGE_SPEC'` and draft the markdown **silently** — no section-by-section walkthrough; that's the express tradeoff. Sources, in priority order: the actual diff, the user's request, the use-case context.

- Open with `# Change Specification: <verb-led title>` and a Change Header / Change Proposal that cites the WHY (quote the user's request as the source).
- Each delta section is a `## N. Title` heading carrying the baseline's own section number and title (e.g. `## 8. Data Model`), placed between the Change Summary Table and the Readiness Checklist. Inside it, use `Add:` / `Change:` / `Remove:` blocks — the `extractSectionDeltas` parser builds the Change Summary Table from those verbs on save; do NOT hand-author the table.
- Include only sections the diff actually touches, plus the mandatory `16` (Migration & Compatibility) and `17` (Affected Test Surface). For 17, name the tests you actually ran/updated in Step 1.
- Mark inferences `[Proposed — needs validation]` — the async reviewers will flag them.

## Step 5 — Confirm once, then persist

Show the user a three-line receipt preview — spec title, use case, baseline — and ask once:

> "Edit's done and verified. Capture it as a change spec in `<workspace>` / `<use case>`? (yes / no / review first)"

On `review first`, show the drafted markdown, then re-ask. On approval:

1. `ideachat_create_session` — `title` = spec title, `description` = one-paragraph summary of the request + diff, `goalType: 'enhance'` (or `'fix'`), `useCaseId`, `maturityStage: 'shaping'`. Capture `chatId`.
2. `spec_document_create` — `workspaceId`, `name`, `specType: 'change'`, `chatId`, `useCaseId`, `baselineSpecDocumentId` (from Step 3), `initialMarkdown` (from Step 4). Capture `specDocId`.
3. `spec_document_update` — same markdown, `docId = specDocId`. This routes through `saveDraft`, which auto-builds the Change Summary Table and runs `validateChangeSpec`. Surface returned errors/warnings verbatim; fix errors before continuing.
4. `spec_review_start` — `workspaceId`, `chatId`, `title`, `useCaseId`, `maturityStage: 'shaping'`, `conversationSummary` = the session description. Reviewers run asynchronously — do not wait for or poll their output.

Skip the readiness pre-flight (`spec_readiness_eval`) — express capture trades gate thoroughness for the async review; the reviewers see the same draft either way.

## Step 6 — Stamp the linkage

If you commit in this session, append the trailer to the commit message:

```
Change-Spec: <specDocId>
```

This trailer is what PR-open capture checks for — a pushed commit carrying it will not be flagged as an uncaptured change. If the user commits themselves, tell them the exact trailer line to include.

## Step 7 — One-line receipt

> "Done — edit verified, captured as `<specDocId>` (review running async: `<deepLink>`). Commit trailer stamped."

That's the whole user-facing footprint of the process. Only surface more if validation errored or reviewers are expected to escalate.

## Out of scope

- No capability/behavior creation (that's `/pm:chat-to-spec-review` Step 6 territory).
- No readiness-gate Q&A loops.
- No editing the spec after the review starts (Spec Review modal / `@specky` owns that).
- One change per invocation — a second request starts a fresh run.
