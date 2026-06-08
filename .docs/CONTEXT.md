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

- "task" was being used to mean both a standalone entity and a checklist line inside a **Note**; resolved: a **Task** is now a first-class entity in the database, always owned by a **Note**. The database is the source of truth for task state, not the Markdown text.
- "habit" was a separate concept with its own tables and API; resolved: habits are now modeled as **Repeating Tasks** — a **Task** with a recurrence interval. The `habits` and `habit_logs` tables are removed.
- "checklist item" was compared to **Attachment**; resolved: a **Task** is a database entity rendered as a widget in the editor, while an **Attachment** is a separate associated asset.
- "routine" was being used for any recurring or delegated agent behavior; resolved: in the current scope, **Routine** is limited to the two precreated daily and weekly **Brief** schedules, while delegated specialized work is a **Subagent**.
- "agent capability" was considered for delegated internal abilities; resolved: because the feature is internal, the canonical term is **Subagent**.
- "Telegram bot token" was being treated like a user identity; resolved: the product uses one official bot, and a **Telegram Link** maps each Telegram sender to a **User**.
- "draft" was considered for the braindump capture surface; resolved: the canonical domain term is **Inbox Note**, and each **User** has at most one.
- "markdown as source of truth for tasks" was the original design; resolved: the database is now the source of truth for **Task** state. The editor renders tasks as interactive widgets and produces Markdown as output, not input.
