# SupaNotes — Domain Terminology & Concepts

A personal notes app with offline support, real-time REST/OT synchronization, and proactive AI capabilities.

## Domain Vocabulary

**Note**:
A rich text document containing paragraphs, headings, lists, images, and tasks. Persisted as a versioned REST/OT JSON document snapshot (`notes.document`).
_Avoid_: Page, entry, file

**Document Snapshot**:
The canonical versioned JSON snapshot for a single note (`schemaVersion: 1`, array of structured blocks). Single source of truth for all note content and task state.
_Avoid_: YDoc, Yjs state, CRDT, document state

**Block**:
A discrete structural node inside a note document (e.g. `header`, `paragraph`, `listItem`, `task`, `image`, `horizontalRule`). Keyed by an immutable string `id`.
_Avoid_: Element, widget, chunk

**Task**:
A block within a note document with `type: "task"` that has text content, checkbox state (`checked`), and optional task metadata (`dueDate`, `dueTime`, `recurrence`). Not an independent root entity — it exists within a note document.
_Avoid_: Todo, action item, checklist item

**Task Occurrence**:
A scheduled instance of a **Task** derived from its due date and recurrence rule. For a recurring task, the current occurrence is the latest scheduled occurrence that has started at the evaluation time. Missed occurrences are not kept as a backlog.
_Avoid_: Task copy, recurring task entity

**Subtask**:
A task block that belongs to exactly one parent task in the same note document.
_Avoid_: Linked task, child item, checklist item

**Task Hierarchy**:
A tree of task blocks within one note document, in which a parent task groups zero or more direct subtasks.
_Avoid_: Task link, dependency graph, checklist

**Assignee**:
The single collaborator (user) assigned to a task within a shared note.
_Avoid_: Task owner, delegate, responsible user

**Reminder / Notification**:
A local notification scheduled relative to a task's due date and time.
_Avoid_: Notification rule, alert time

**Task Completion**:
An event record created in `task_completions` when a task transitions to completed. Derived by the relational projection from document snapshot changes, never written directly by custom UI endpoints.
_Avoid_: Completion log, history entry

**Projection**:
Derived relational data (`tasks` table, `task_completions` table) computed deterministically from the canonical REST/OT document snapshot by `TaskProjectionEngine`. Read-only — never written to directly by the UI.
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

- A **Note** contains zero or more **Task** blocks.
- A **Task** may be the parent of zero or more **Subtasks**.
- A **Subtask** belongs to exactly one parent **Task**.
- A **Task Hierarchy** is stored as part of one canonical **Document Snapshot** and can be surfaced in global task views.

## Example dialogue

> **Dev:** "Is `Fazer aulas` only linked to `Tirar carteira`?"
> **Domain expert:** "No. It is a **Subtask** of the parent **Task** `Tirar carteira`, so its completion contributes to the parent's progress."

## Flagged ambiguities

- "Vincular" was used ambiguously for both a generic reference and a parent-child relationship — resolved: use **Task Hierarchy**, **parent Task**, and **Subtask** for this feature.
- A hierarchy spanning multiple notes was considered and rejected: a **Task Hierarchy** remains within one note, even when shown in global task views.
- A future task-only page could be mistaken for independent task ownership — resolved: a global task view may read the projection, but every mutation must resolve the owning **Note** and enter through that note's canonical REST/OT session. A **Task** never exists as an independently mutable root entity.

## Resolved Architecture Decisions

- **Task mutation seam**: User-intent task mutations enter through REST/OT document operations. `tasks` and `task_completions` remain projections. Candidate 01 removes or narrows the legacy direct mutation APIs exposed by `ITasksRepository`, `TasksLocalRepository`, and `TasksDao`, and updates their tests. `syncProjectedTasksForNoteTyped` and other projector-owned persistence remain valid because they persist derived data.
- **Task mutation test seam**: Tests for user-intent task changes cover the canonical document-operation flow. DAO tests cover task projection persistence, not direct task mutation APIs. Completion-history projection is a separate follow-up because the current canonical projector does not yet populate `task_completions`.
- **Operation contract scope**: Candidate 06 deepens the Dart-Go operation seam. `NoteOperationContract` centralizes Flutter wire names/builders and rejects malformed captured payloads before the outbox; `backend/internal/noteoperations` remains the authoritative validator and applier, including payload rules for `set_block_metadata` and `complete_task_occurrence`. The shared `test/fixtures/operation_contract.json` keeps one valid example for every operation kind.
- **Legacy task API removal**: The direct task mutation APIs are removed immediately, without a deprecation period, because no production caller owns them. Read queries and projector-owned writes remain available.
- **Completion DAO boundary**: Candidate 01 removes only the legacy `TaskCompletionsDao.recordCompletion` and `undoLastCompletion` helpers, plus the `TasksDao.completionsDao` wiring that exists solely for them. Completion upserts and reads remain available for the separate canonical completion-history projection.
- **Task query naming**: `ITasksRepository` and `TasksRepository` remain the read facade names for Candidate 01. The interface becomes read-only without a rename because the project already uses the `I...Repository` convention and the facade already documents its query role.
- **Task projection write entry**: Candidate 01 keeps `TasksDao.syncProjectedTasksForNoteTyped` as the task-row projection entry and removes the unused raw `TasksDao.upsertFromRemote` adapter. Completion remote upserts remain for the separate completion-history projection.
- **Task transaction boundary**: Candidate 01 removes the unused task-module `runInTransaction` wrappers. Transaction ownership remains with the document/sync persistence services and the typed projection save path.
- **Legacy task test cleanup**: Tests that assert the old DAO completion semantics are removed or replaced by canonical command, editor, operation-capture, and projection tests. Legacy recurring-task expectations must not be carried forward when they conflict with the document contract.
- **Editor test boundary**: Note editor widget tests observe document/controller effects and snackbar callback behavior. They do not mock or verify legacy task-repository mutation methods.
- **Candidate 01 completion criteria**: The task feature exposes no user-intent mutation path through repositories or DAOs; typed task projection remains the only task-row projection entry; legacy completion helpers and transaction escape hatches are gone; editor, command, operation-capture, and projection tests cover the canonical behavior; focused analyzer and Flutter test checks pass.
- **Recurring occurrence policy**: A recurring task exposes only the latest occurrence that has started at evaluation time. Missed occurrences do not form a backlog. Date arithmetic remains a pure recurrence concern, while occurrence resolution and completion transitions use an explicit clock.
- **Recurring occurrence seam**: Candidate 03 may deepen the occurrence domain module around current-occurrence resolution and completion transition results. The editor remains an adapter that mutates the canonical REST/OT document, and `NoteDocumentProjector` remains the adapter for relational projections. No independent task or occurrence persistence path is introduced.
- **Recurring occurrence validation**: Before implementation, characterization tests must preserve non-recurring behavior, daily/weekday/weekly/monthly rules, all-day and timed tasks, missed occurrences, month-end clamping, and completion metadata. A future rule change must update the domain policy and its tests rather than separate caller-specific date interpretations.
- **Desktop contextual formatting**: An expanded text selection on desktop opens a contextual formatting toolbar automatically. Its inline actions use `NoteEditorCommands` and the canonical editor operation flow; the existing persistent toolbar remains responsible for document-level actions.
- **Markdown shortcut conversion**: Desktop typing converts supported Markdown shortcuts into semantic document content. `# `, `## `, `### `, list markers, and `> ` create structural blocks; inline markers create attributions. `[] ` and standard `- [ ] ` create an unchecked `TaskNode`, remove the marker, and preserve the task text. The conversion must enter through `Editor` requests so REST/OT capture remains canonical.



