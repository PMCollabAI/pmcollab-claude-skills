---
description: Turn the current Claude chat into a brand-new PMCollab UseCase with BXT detail bullets via usecase_create.
---

# /pm:chat-to-usecase

Create a brand-new PMCollab `UseCase` from the in-progress conversation. Drafts the BXT detail bullets from chat context, fills the essential gaps via targeted follow-ups, and persists via the `usecase_create` MCP tool. The greenfield counterpart to `/pm:chat-to-spec-review` (which requires a use case to already exist).

## Hard rules

- **Never invent IDs.** Workspace id and persona id come from MCP tool responses.
- **Confirm before the `usecase_create` call.** Creation is visible to workspace collaborators via socket events.
- **One use case per invocation.** Do not bulk-create.
- **Refuse on duplicate title.** If `usecase_create` returns `isError` with `error: 'duplicate_title'`, surface the existing id + title and stop — do not retry with a slightly different name to dodge the check.
- **Don't fabricate detail bullets.** If a non-essential field isn't covered in the chat, omit it. If an *essential* field isn't covered, ask the user — never write `[Needs Input]` into a detail bullet (that's a spec template concept, not a use case concept).

## Step 1 — Resolve workspace

Run the `/pm:select-workspace` flow (see `commands/select-workspace.md` in this plugin) to resolve `workspaceId` + cached identity (`userId`, `email`, `createdByName`). Use cases are workspace-scoped; do not run `/pm:select-usecase` — we're creating one.

## Step 2 — Distill the chat into a draft

Walk the conversation and extract every field that's clearly stated. The 10 detail-bullet fieldNames the MCP tool accepts are:

- `problem` — what's broken or missing today
- `idea` — solution approach (if discussed)
- `businessObjective` — why this matters to the business
- `keyResults` — how success is measured
- `primaryStakeholder` — executive sponsor / decision-maker
- `strategicFit` — alignment with strategy (1–5 scale + notes)
- `keyPersonas` — end users + roles
- `valueProposition` — benefits for those personas
- `changeResistance` — adoption obstacles
- `safeguards` — security / compliance considerations

Plus the use case itself needs:

- `title` — verb-led, ≤200 chars (e.g. "Auto-tag time entries from window context")
- `description` — one-sentence summary

**Essentials.** These four MUST be present before the `usecase_create` call:

- `title`
- `problem`
- `businessObjective`
- One of: `keyPersonas` OR `valueProposition` (whoever benefits, or how they benefit)

## Step 3 — Ask follow-ups for missing essentials

For each essential field not clearly covered, ask ONE focused question at a time. Do not paste a checklist. Examples:

- title missing → "What's a short verb-led title for this? Something like 'Auto-tag time entries' rather than 'Time tracking improvements'."
- problem missing → "What's the core problem this use case is solving? What's broken or missing today?"
- businessObjective missing → "Why does this matter to the business right now? What gets unlocked when it ships?"
- keyPersonas missing → "Who are the key personas this benefits? Names + roles if you have them."
- valueProposition missing → "What's the value proposition for those personas? What's better for them after this ships?"

The user can answer "skip" or "I don't know yet" for non-essential fields — in that case, omit the bullet rather than fabricate a placeholder. For an essential field, push back once: "I need this one to create a meaningful use case — even a one-line answer is fine." If they still skip, stop the command rather than create a hollow row.

## Step 4 — Render the draft and confirm

Render the draft so the user sees what will be persisted:

```
Draft use case for workspace "<workspace title>":

Title:        <title>
Description:  <description>
Status:       draft
Source:       idea-chat

Detail bullets:
- problem:            <text>
- businessObjective:  <text>
- keyPersonas:        <text>
- valueProposition:   <text>
[any additional bullets here]

Create this use case? (yes / edit <field> / cancel)
```

On `edit <field>`, ask for the new value, update the draft, re-render.
On `cancel`, stop cleanly.
On `yes`, continue.

## Step 5 — Call `usecase_create`

Invoke the MCP tool with:

```json
{
  "workspaceId": "<from Step 1>",
  "title": "<from draft>",
  "description": "<from draft>",
  "createdBy": "<userId from cached identity>",
  "createdByName": "<createdByName from cached identity>",
  "source": "idea-chat",
  "status": "draft",
  "detailBullets": [
    { "fieldName": "problem", "text": "..." },
    { "fieldName": "businessObjective", "text": "..." },
    { "fieldName": "keyPersonas", "text": "..." },
    { "fieldName": "valueProposition", "text": "..." }
  ]
}
```

If the response is `isError` with `error: 'duplicate_title'`, surface:

> "A use case titled **<existingTitle>** already exists (id: `<existingUseCaseId>`). Open it in PMCollab to extend it, or rephrase the title and re-run this command."

Then stop. Do NOT retry with a tweaked title — let the user choose.

On success, capture `useCase.id` and `detailBullets[].id`.

## Step 6 — Recap

Print:

- **Workspace:** `<title>`
- **New use case:** `<title>` (id: `<id>`, status: draft)
- **Detail bullets created:** `<count>` (`<comma-separated fieldName list>`)
- **Next step:** "Run `/pm:chat-to-spec-review` to author a spec for this use case, or `/pm:load-usecase-context` to load it into another workflow."

## Out of scope

- Editing or deleting an existing use case (use the PMCollab web app).
- Creating capabilities or behaviors (that's the optional Step 6 of `/pm:chat-to-spec-review`).
- Promoting the use case to a CanonicalObject (standard promotion flow).
- Linking detail bullets to existing personas — the MCP tool accepts `linkedPersonaId` per bullet but this command doesn't yet enumerate available personas.
- Bulk-creating multiple use cases in one run.
