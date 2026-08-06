# 03 — Markdown task shortcuts

**What to build:** While typing in the desktop note editor, convert `[] ` and
the standard `- [ ] ` task marker into an unchecked task. The marker must be
removed, the remaining text must become the task text, and the result must
behave exactly like a task created through the existing editor commands.

**Blocked by:** None — can start immediately.

**Status:** implemented

- [x] Typing `[] ` at the start of an editable line creates an unchecked
      `TaskNode`.
- [x] Typing `- [ ] ` at the start of an editable line creates the same
      unchecked `TaskNode` instead of an unordered list item.
- [x] Task conversion has precedence over the generic `- ` list shortcut when
      the full task marker is present.
- [ ] The marker is removed and all text after it remains in the task.
- [ ] The created task uses the existing checkbox rendering, completion
      behavior, metadata model, and task hierarchy rules.
- [ ] The editor places the caret in the task text after conversion.
- [ ] The task mutation is captured as a canonical document operation and is
      available to the normal outbox and synchronization flow.
- [x] No direct write is made to the relational task or completion projection.
- [ ] Local snapshot reconstruction and pending-operation replay preserve the
      task node and its text.
- [ ] Focused tests cover both syntaxes, precedence, empty and non-empty task
      text, marker removal, caret placement, operation capture, and projection
      behavior.
