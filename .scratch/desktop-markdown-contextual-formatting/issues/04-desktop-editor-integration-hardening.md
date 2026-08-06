# 04 — Desktop editor integration and regression hardening

**What to build:** Integrate the contextual formatting popover and Markdown
shortcuts into one reliable desktop writing flow. A user should be able to
select, format, navigate, type structural shortcuts, create tasks, work
offline, and resume editing without stale overlays, lost selection, or broken
canonical synchronization.

**Blocked by:** 01 — Desktop contextual formatting popover; 02 — Markdown
block and inline shortcuts; 03 — Markdown task shortcuts.

**Status:** ready-for-agent

- [ ] The formatting popover and Markdown reactions work together without
      competing overlays or stale selection state.
- [ ] Cursor navigation and desktop keyboard editing continue to work after
      the popover opens, closes, or applies a command.
- [ ] Scrolling the editor keeps the contextual popover positioned correctly
      or hides it when the selection is no longer visible.
- [ ] The desktop editor remains usable at supported narrow and wide desktop
      sizes without overflow or clipped controls.
- [ ] Reduced-motion settings reach the same final states without requiring
      animation timing assumptions.
- [ ] High-contrast or opaque-surface rendering keeps the popover readable and
      its controls distinguishable.
- [ ] Keyboard navigation and assistive technology expose the popover actions,
      active states, and dismissal behavior.
- [ ] Local editing with no network preserves the converted blocks and
      formatting in the outbox.
- [ ] Restart or snapshot reconstruction preserves headings, lists,
      blockquotes, attributions, and task nodes created by shortcuts.
- [ ] Remote synchronization and rebase do not create duplicate markers,
      duplicate task nodes, or lost formatting.
- [ ] Focused editor, toolbar, command, operation-capture, projection, and
      contract tests pass, followed by Flutter analysis.
- [ ] The validation report distinguishes new coverage from existing tests and
      does not claim a desktop visual run unless one was executed.
