# SupaNotes — Domain Terminology & Concepts

A personal notes app with offline support, real-time REST/OT synchronization, and proactive AI capabilities.

## Domain Vocabulary

**Note**:
A rich text document containing paragraphs, headings, lists, images, and tasks. Persisted as a versioned REST/OT JSON document snapshot (`notes.document`).
_Avoid_: Page, entry, file

**Note Icon**:
An optional shared visual symbol for a **Note**, represented by either a native-color Unicode emoji or a color-selected icon from the application's fixed catalog.
_Avoid_: Note image, thumbnail, title prefix

**Display Title**:
The read-only name derived from the first non-empty textual **Block** of a **Note**.
_Avoid_: Stored title, title field, separately editable note name

**Share Link**:
A revocable secret link that grants read-only access to a **Note** and its attachments to any person who possesses it, without requiring a SupaNotes account.
_Avoid_: Public note, note URL, invitation link

**Direct Share**:
An access grant that identifies one registered SupaNotes user and assigns `view` or `edit` permission to a **Note**.
_Avoid_: Share Link, public access, email link

**Document Snapshot**:
The canonical versioned JSON snapshot for a single note (`schemaVersion: 1`, array of structured blocks). It is the single source of truth for that note's content and for the state of its `TaskNode`s; it is not the storage for independent tasks.
_Avoid_: YDoc, Yjs state, CRDT, document state

**Block**:
A discrete structural node inside a note document (e.g. `header`, `paragraph`, `listItem`, `task`, `image`, `horizontalRule`). Keyed by an immutable string `id`.
_Avoid_: Element, widget, chunk

**TaskNode (note task)**:
A block within a note document with `type: "task"` that has text content, checkbox state (`checked`), and optional task metadata (`dueDate`, `dueTime`, `recurrence`). Its canonical state lives in that note's document snapshot and it is addressed by `noteId` + `blockId`.
_Avoid_: Todo, action item, checklist item

**Task (independent task)**:
An independently-owned root entity in the backend `tasks` table, with a local-first copy in the Drift `tasks` table. It is created, edited, completed, reopened and deleted through the task API/repository and is not a `TaskNode` or a projection of one.
_Avoid_: StandaloneTask, TaskModel, task copied from a note

**Task Occurrence**:
A scheduled instance of either a **TaskNode** or an independent **Task**, derived from its due date and recurrence rule. For a recurring task, the current occurrence is the latest scheduled occurrence that has started at the evaluation time. Missed occurrences are not kept as a backlog.
_Avoid_: Task copy, recurring task entity

**Subtask**:
A task block that belongs to exactly one parent task in the same note document.
_Avoid_: Linked task, child item, checklist item

**Task Hierarchy**:
A tree of task blocks within one note document, in which a parent task groups zero or more direct subtasks.
_Avoid_: Task link, dependency graph, checklist

**Assignee**:
The single collaborator (user) assigned to a task within a shared note. Independent-task sharing and assignees are a future extension around the same independent task identity.
_Avoid_: Task owner, delegate, responsible user

**Reminder / Notification**:
A local notification scheduled relative to a task's due date and time.
_Avoid_: Notification rule, alert time

**Task Completion**:
For a `TaskNode`, completion state and history live in the canonical note document. For an independent **Task**, non-recurring completion uses `lastCompletedAt` and recurring history uses `completions` in the independent task row. The old `task_completions` relation is retained only as quarantined migration evidence and is not a current runtime source.
_Avoid_: Completion log, history entry

**Projection**:
Derived data used for a read view. The current Tasks tab combines read adapters for `TaskNode`s and independent `Task`s locally; neither the backend nor local `tasks` table is a projection of the other source. `TaskProjectionEngine` and the old relational task projection are historical migration terminology, not a current runtime contract.
_Avoid_: Materialized view, cache, index

**Vault**:
The entirety of a user's data — all notes, tasks, attachments, and preferences.
_Avoid_: Account, workspace, library

**Drawing Block**:
A block within a note document (`type: "drawing"`) that contains vector stroke data and rendering properties for freehand drawings and sketches embedded within the block sequence. Edited inline directly inside the note with an explicit drawing-mode activation toggle to avoid gesture conflicts with document scrolling.
_Avoid_: Canvas overlay, sketch file, scribbles

**Markdown Shortcut**:
An editor input pattern that is converted immediately into a semantic document block or inline attribution while typing. Structural markers are not retained as literal note text after conversion.
_Avoid_: Markdown source mode, display-only Markdown

**Contextual Formatting Toolbar**:
A desktop popover anchored to an expanded text selection that exposes inline formatting actions such as bold, italic, and strikethrough. It is separate from the persistent editor toolbar for document-level actions.
_Avoid_: Selection menu, document toolbar

## Relationships

- A **Note** has zero or one **Note Icon**.
- A **Note** has one derived **Display Title**, including the empty-note fallback.
- A **Note** has zero or one active **Share Link**.
- An active **Share Link** grants read-only access to exactly one **Note**.
- Replacing a **Share Link** invalidates the previous link immediately.
- A **Share Link** remains valid until the owner disables or replaces it; it has no automatic expiration.
- A person who possesses an active **Share Link** may read its **Note** without becoming a collaborator.
- A **Share Link** exposes the current **Document Snapshot**, not a frozen copy from the time the link was created.
- A loaded **Share Link** page keeps its rendered snapshot until the visitor reloads it; it does not receive live updates.
- A **Share Link** grants read access to the **Note** attachments but never grants permission to upload, change, or delete them.
- Invalidating a **Share Link** also ends access to the **Note** attachments through that link.
- A **Share Link** is an HTTPS URL that has a responsive browser destination and does not require the SupaNotes app.
- An installed SupaNotes app may claim a **Share Link** through its platform link association; otherwise the same URL opens the browser destination.
- The app may use a valid **Share Link** for read-only guest access without an authenticated account.
- When an authenticated account has a stronger permission than the **Share Link**, the stronger account permission applies.
- A **Share Link** does not disclose the owner identity unless that identity is part of the **Note** content.
- A **Share Link** may expose only the **Display Title** to an external preview service; it never exposes an excerpt, image, or attachment in preview metadata.
- External preview metadata uses `Nota compartilhada no SupaNotes` when the **Note** has no **Display Title**.
- A **Share Link** has no product-level visitor identity, reader history, or view counter.
- Read-only access through a **Share Link** permits copying, printing, and attachment downloads but never a **Note** mutation.
- Only the **Note** owner may create, replace, or disable its **Share Link**.
- A **Share Link** exists only after explicit owner activation; opening sharing controls never creates one.
- Deleting a **Note** invalidates its **Share Link** permanently; restoring the **Note** does not reactivate that link.
- A **Note** may have both user-specific **Direct Shares** and one active **Share Link**.
- A **Direct Share** makes the identified user a collaborator; a **Share Link** does not.
- A **Share Link** does not grant access to another **Note** referenced by an internal `note://` link.
- A **Note** contains zero or more **TaskNode** blocks.
- An independent **Task** belongs to exactly one owner and is not contained in a **Note**.
- A **TaskNode** may be the parent of zero or more **Subtasks**.
- A **Subtask** belongs to exactly one parent **TaskNode** in the same note document.
- A **Task Hierarchy** is stored as part of one canonical **Document Snapshot**; independent tasks do not join that hierarchy. Both sources can be surfaced in global task views without being copied or linked.

## Example dialogue

> **Dev:** "Is `Fazer aulas` only linked to `Tirar carteira`?"
> **Domain expert:** "No. It is a **Subtask** of the parent **Task** `Tirar carteira`, so its completion contributes to the parent's progress."
>
> **Dev:** "Must a person have an account to open a **Share Link**?"
> **Domain expert:** "No. Possession of an active **Share Link** grants read-only access, but it does not make the person a collaborator."

## Flagged ambiguities

- "Icon" was used for both an emoji and an application glyph — resolved: **Note Icon** includes both variants but excludes custom images.
- "Icon color" applies only to catalog icons — resolved: emojis keep their native colors and have no configurable background.
- A **Note Icon** was considered as a personal preference — resolved: it belongs to the **Note** and is shared by all collaborators.
- "Title" was considered as separately stored note data — resolved: the **Display Title** is derived from document content and is never edited independently.
- "A link that gives access" was ambiguous between a locator and an authorization grant — resolved: a **Share Link** is a revocable read-only grant for any person who possesses it.
- Multiple simultaneous links for one **Note** were considered and rejected: replacing its **Share Link** invalidates the previous link.
- Automatic expiration was considered and rejected: the owner controls when a **Share Link** becomes invalid.
- App-only access was considered and rejected: every **Share Link** must work in a browser without an installed app.
- App and web URLs were considered as separate resources and rejected: one canonical HTTPS **Share Link** supports native app handoff and browser fallback.
- Opening a **Share Link** in the app was considered as a permission downgrade and rejected: owner or `edit` account access remains stronger than link-based read access.
- Owner attribution on the public page was considered and rejected: account identity is private unless the owner writes it in the **Note**.
- A fully generic external preview was considered and rejected: preview metadata may include the **Display Title**, but no other note content.
- Visitor tracking and view counts were considered and rejected: anonymous access does not create a product-level reader history.
- Copy and print restrictions were considered and rejected: read-only means no mutation, not digital rights enforcement.
- An `edit` collaborator was considered for **Share Link** management and rejected: editing content does not include authority to grant anonymous access.
- "Sharing" was used for both identified collaboration and anonymous access — resolved: use **Direct Share** for a registered collaborator and **Share Link** for possession-based read access; both may coexist on one **Note**.
- Automatic link creation when opening sharing controls was considered and rejected: anonymous access requires explicit owner activation.
- Link restoration after note recovery was considered and rejected: a restored **Note** requires a newly activated **Share Link**.
- A frozen copy was considered and rejected: a **Share Link** always resolves the current **Document Snapshot**.
- Live updates in an open public page were considered and rejected: changes appear after a browser reload.
- Internal links were considered as transitive access and rejected: the public reader renders `note://` text without navigation, while external web links remain actionable.
- Text-only access was considered and rejected: a **Share Link** includes the attachments that belong to its **Note**.
- "Vincular" was used ambiguously for both a generic reference and a parent-child relationship — resolved: use **Task Hierarchy**, **parent Task**, and **Subtask** for this feature.
- A hierarchy spanning multiple notes was considered and rejected: a **Task Hierarchy** remains within one note, even when shown in global task views.
- A task-only page could be mistaken for one storage model — resolved: the global Tasks view reads independent **Task** rows and `TaskNode` adapters, preserving each source's owner and mutation path. It never copies one source into the other.

## Current task ownership contract

The current implementation has two authorities with a shared presentation
boundary:

- `TaskNode` lives in `notes.document` and the effective local note snapshot.
  Note editor mutations use REST/OT operations and never write the independent
  task tables.
- `Task` (the independent task) lives in the backend `tasks` table. The local
  Drift `tasks` table is its local-first copy, and `pending_task_operations` is
  its durable outbox. `TaskRepository` and `/api/v1/tasks` own these writes.
- The two `tasks` tables above are independent-task storage at their respective
  layers, not a projection of `TaskNode`. There is no projection, automatic
  conversion, or automatic copy between a note task and an independent task.
- The Tasks tab may mix the two read sources in `TaskListItem`; this is a
  non-persisted view model. `NoteTask` carries `noteId` and `blockId` back to the
  document, while `Task` mutations remain independent.
- PostgreSQL `tasks_legacy_quarantine_v31` and
  `task_completions_legacy_quarantine_v31`, plus their SQLite quarantine
  counterparts, are retained migration evidence only. They are not runtime
  task sources.

## Historical note-only architecture decisions (retained evidence)

The following records decisions from the completed note-document migration,
when the product had no independent task resource. They remain normative for
`TaskNode` behavior, but are superseded by the current ownership contract for
the independent `Task`. References to relational projections in this section
describe that historical migration and must not be implemented as new runtime
paths.

- **Historical note-task mutation seam**: During the note-only migration, user-intent mutations for `TaskNode` entered through REST/OT document operations. That rule still applies to note tasks. It does not apply to the separate independent `Task`, whose mutations enter through `TaskRepository` and `/api/v1/tasks`. The old projection helpers named here are migration evidence, not a current path for either source.
- **Task mutation test seam**: Note-task tests cover the canonical document-operation flow; independent-task tests cover the task repository/API, outbox and idempotent sync. Neither source is tested by converting or copying the other.
- **Operation contract scope**: Candidate 06 deepens the Dart-Go operation seam. `NoteOperationContract` centralizes Flutter wire names/builders and rejects malformed captured payloads before the outbox; `backend/internal/noteoperations` remains the authoritative validator and applier, including payload rules for `set_block_metadata` and `complete_task_occurrence`. The shared `test/fixtures/operation_contract.json` keeps one valid example for every operation kind.
- **Legacy task API removal**: The direct task mutation APIs from the former note-task projection were removed without a deprecation period. The current independent-task API is a different resource and is documented by `backend/internal/tasks`.
- **Completion DAO boundary**: The old `TaskCompletionsDao` helpers belonged to the legacy note-task projection and remain historical evidence only. Note completion history is in `TaskNode`; independent completion history is in the independent `Task` row (`completions` / `lastCompletedAt`).
- **Task query naming**: `ITasksRepository` and `TasksRepository` remain the read facade names for Candidate 01. The interface becomes read-only without a rename because the project already uses the `I...Repository` convention and the facade already documents its query role.
- **Task projection write entry**: `TasksDao.syncProjectedTasksForNoteTyped` was a historical note-projection entry. It must not be used to populate the current independent-task tables; independent persistence is owned by `TaskRepository`/`TasksDao` transactions for `Task` rows and their outbox.
- **Task transaction boundary**: Note document/sync services own `TaskNode` snapshot persistence. Independent task repository transactions own the local `Task` row and its pending operation; there is no cross-source transaction.
- **Legacy task test cleanup**: Tests that assert the old DAO completion semantics are removed or replaced by canonical command, editor, operation-capture, and projection tests. Legacy recurring-task expectations must not be carried forward when they conflict with the document contract.
- **Editor test boundary**: Note editor widget tests observe document/controller effects and snackbar callback behavior. They do not mock or verify legacy task-repository mutation methods.
- **Historical Candidate 01 completion criteria**: The note-only task feature exposed no user-intent mutation path through its former projection repositories/DAOs; those criteria are retained to explain the completed migration, not to prohibit the current independent `TaskRepository` mutation path.
- **Recurring occurrence policy**: A recurring task exposes only the latest occurrence that has started at evaluation time. Missed occurrences do not form a backlog. Date arithmetic remains a pure recurrence concern, while occurrence resolution and completion transitions use an explicit clock.
- **Recurring occurrence seam**: The shared occurrence policy is used by both sources. The note editor remains the adapter that mutates `TaskNode` in the canonical REST/OT document; the independent task repository mutates `Task` through its own API/outbox. Neither source is projected into the other.
- **Recurring occurrence validation**: Before implementation, characterization tests must preserve non-recurring behavior, daily/weekday/weekly/monthly rules, all-day and timed tasks, missed occurrences, month-end clamping, and completion metadata. A future rule change must update the domain policy and its tests rather than separate caller-specific date interpretations.
- **Desktop contextual formatting**: An expanded text selection on desktop opens a contextual formatting toolbar automatically. Its inline actions use `NoteEditorCommands` and the canonical editor operation flow; the existing persistent toolbar remains responsible for document-level actions.
- **Markdown shortcut conversion**: Desktop typing converts supported Markdown shortcuts into semantic document content. `# `, `## `, `### `, list markers, and `> ` create structural blocks; inline markers create attributions. `[] ` and standard `- [ ] ` create an unchecked `TaskNode`, remove the marker, and preserve the task text. The conversion must enter through `Editor` requests so REST/OT capture remains canonical.



