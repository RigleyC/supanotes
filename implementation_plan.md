# Implementation plan — local-first note persistence

Status: complete for ticket 01.

Scope: ticket 01, atomic local persistence during remote note hydration.

- [x] Confirm the current write order and data-loss failure mode.
- [x] Expose a pure document projection result.
- [x] Persist document, catalog row, content projection, and task projection atomically.
- [x] Update catalog hydration to use the aggregate transaction.
- [x] Add first-hydration and rollback tests.
- [x] Run focused tests, full suite, code review, and commit the ticket.
