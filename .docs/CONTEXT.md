# Notes Agent

Glossary for the core note-taking domain, with emphasis on what is canonical in the database versus what exists as supporting structure for retrieval and automation.

## Language

**User**:
The person who owns notes, settings, memories, routines, and external channel links in the product.
_Avoid_: Telegram account, bot user

**Note**:
The primary user-owned document whose content is stored as Markdown. The editor renders Markdown elements (headings, lists, etc.) as interactive widgets; the Markdown text is output, not raw user input.
_Avoid_: File, task list

**Inbox Note**:
A single special **Note** per **User** used for unstructured capture before its content is organized into regular notes.
_Avoid_: Draft, searchable note, temporary note, multiple inboxes

**Task**:
A trackable unit of work stored as its own entity in the database. Every **Task** belongs to exactly one **Note**. A **Task** may have a due date, a recurrence interval, and a completion state. When rendered in the editor, it appears as a checkbox widget inline in the **Note**'s body.
_Avoid_: Checklist line, habit, standalone task manager entry

**Repeating Task**:
A **Task** with a recurrence interval configured (daily, weekdays, weekly, or monthly). When a **Repeating Task** is completed, it is automatically reopened with a new due date based on the chosen interval. The task content remains the same; only the due date advances.
_Avoid_: Habit, cron job, routine

**Attachment**:
A separate asset associated with a **Note** through metadata and storage references.
_Avoid_: Task, embedded file text

**Brief**:
A daily or weekly digest generated for the user from their notes, memories, and pending context.
_Avoid_: Routine, generic report

**Subagent**:
A focused internal agent the main agent can delegate to when a request needs specialized retrieval, analysis, or note transformation.
_Avoid_: Routine, user-facing agent, generic tool

**Routine**:
A precreated schedule record that delivers either the daily or weekly **Brief** at selected days and times.
_Avoid_: Custom automation, arbitrary routine, agent capability

**Telegram Link**:
The association between a Notes Agent **User** and a Telegram sender identity used by the official product bot.
_Avoid_: Bot token, Telegram account as user record

## Relationships

- A **Note** contains zero or more **Tasks**
- A **Task** belongs to exactly one **Note**
- A **Task** without an explicit **Note** is assigned to the user's **Inbox Note**
- A **Repeating Task** is a **Task** with a non-null recurrence interval
- A **User** has at most one **Inbox Note**
- An **Inbox Note** is created by default and is excluded from search, RAG, deletion, and archiving
- An **Attachment** belongs to one **Note**
- A **Routine** delivers a **Brief**
- The daily **Routine** can run on multiple weekdays; the weekly **Routine** runs on exactly one weekday
- A **Subagent** can inspect or transform one or more **Notes**
- A **Telegram Link** belongs to one **User**

## Example dialogue

> **Dev:** "When a user checks off a task, do we update the Markdown first?"
> **Domain expert:** "No. The system updates the **Task** entity in the database. The editor widget reflects the new state, and the Markdown output is regenerated from the entity — the database is the source of truth, not the Markdown text."

> **Dev:** "What happens when a repeating task is completed?"
> **Domain expert:** "A completion record is saved for history, and the **Task** is reopened with a new due date calculated from the recurrence interval. The content stays the same."

## Flagged ambiguities

- **"save" versus "sync"**: A **save** is a local persistence operation (Drift). A **sync** is a network push/pull operation. The user should never perceive either; the UI reflects the local database immediately. The network is an implementation detail.
- **"flush"**: A **flush** is an immediate, synchronous-or-near-synchronous **save** that bypasses the debounce. Used when the user leaves the editing surface so that no in-flight edits are lost.
- "task" was being used to mean both a standalone entity and a checklist line inside a **Note**; resolved: a **Task** is now a first-class entity in the database, always owned by a **Note**. The database is the source of truth for task state, not the Markdown text.
- "task status" was drifting between `pending`, `open`, `in_progress`, `done`, and `completed`; resolved: in v1 a **Task** is either open or done. Due dates, expiration-like behavior, and recurrence are metadata on the **Task**, not additional status values.
- "repeating task completion" was ambiguous between creating a new task per occurrence and moving the same task forward; resolved: completing a **Repeating Task** records a completion event, advances the same **Task** to its next due date, and leaves it open for the next occurrence.
- "`completed_at` on tasks" was ambiguous because repeating tasks reopen; resolved: `tasks.completed_at` means the most recent completion timestamp. The current state still comes from the **Task** status, and `task_completions` remains the completion history.
- "expired task" was used to mean a task whose due date has passed; resolved: in v1 this is an overdue **Task**, derived from `due_date` and current date. Tasks do not expire, disappear, or close automatically.
- "`due_date` on task completions" was unclear; resolved: `task_completions.due_date` stores the due date of the occurrence that was completed, while `completed_at` stores when the user actually completed it.
- "habit" was a separate concept with its own tables and API; resolved: habits are now modeled as **Repeating Tasks** — a **Task** with a recurrence interval. The `habits` and `habit_logs` tables are removed.
- "checklist item" was compared to **Attachment**; resolved: a **Task** is a database entity rendered as a widget in the editor, while an **Attachment** is a separate associated asset.
- "routine" was being used for any recurring or delegated agent behavior; resolved: in the current scope, **Routine** is limited to the two precreated daily and weekly **Brief** schedules, while delegated specialized work is a **Subagent**.
- "cron expression" was leaking into the **Routine** contract; resolved: in v1 a **Routine** is scheduled with selected weekdays, a time of day, and an enabled flag. Cron may exist internally, but it is not product language or public API.
- "sync scope" was unclear for note relationships; resolved: v1 sync includes notes, tasks, contexts, tags, note tags, note links, and task completions.
- "sync pagination" was proposed for first-open full sync; resolved: v1 may use a non-paginated incremental pull because the initial product is personal and small-scale. Cursor pagination is deferred until dataset size makes it necessary.
- "Riverpod code generation" appeared in dependencies while the project uses manual providers; resolved: v1 uses manual Riverpod providers only, defaults feature providers to autoDispose, and represents async loading/error with AsyncValue when shared state needs those states.
- "offline behavior" was incomplete for online-only features; resolved: v1 keeps notes and tasks usable offline, while agent chat, search, routines, settings, and Telegram linking show a simple offline-disabled state.
- "agent capability" was considered for delegated internal abilities; resolved: because the feature is internal, the canonical term is **Subagent**.
- "Telegram bot token" was being treated like a user identity; resolved: the product uses one official bot, and a **Telegram Link** maps each Telegram sender to a **User**.
- "Telegram chat id" was being used as identity; resolved: a **Telegram Link** identifies the sender by `telegram_user_id` from `message.from.id`. `telegram_chat_id` is only the current delivery target for bot replies.
- "Telegram streaming" was considered optional polish; resolved: in v1 the Telegram gateway streams assistant output progressively by editing a bot message while the agent response is generated.
- "draft" was considered for the braindump capture surface; resolved: the canonical domain term is **Inbox Note**, and each **User** has at most one.
- "quick capture" was expected to append to the **Inbox Note** from the FAB; resolved: in v1 the main app FAB creates a new **Note** directly. The **Inbox Note** remains available for unstructured capture and later organization, but it is not the default FAB target.
- "inbox organization" was uncertain after the FAB changed to create new notes; resolved: organizing the **Inbox Note** with an agent-generated, user-confirmed plan remains a v1 feature.
- "`create_section` in inbox organization" was part of the broader scope; resolved: v1 inbox organization supports appending to an existing note, creating a new note, or keeping a snippet in the **Inbox Note**. Creating a new section inside an existing note is deferred.
- "markdown as source of truth for tasks" was the original design; resolved: the database is now the source of truth for **Task** state. The editor renders tasks as interactive widgets and produces Markdown as output, not input.
