# ADR 0009 — Recurring Task Occurrence Policy

Status: Accepted

Date: 2026-08-04

## Context

SupaNotes stores task metadata in the canonical REST/OT note document. A
recurring task has a due date, a recurrence rule, and sparse completion
metadata for completed scheduled dates.

The current implementation already has pure date arithmetic in
`lib/core/utils/recurrence.dart`, but callers still interpret the current
occurrence in several places: completion transitions, occurrence status,
document projection, and editor metadata adaptation. A rule change can
therefore make the editor, task projection, and task views disagree.

## Decision

- The current occurrence is the latest scheduled occurrence that has started
  at the evaluation time.
- Missed occurrences are not kept as a permanent backlog.
- An overdue occurrence remains the visible occurrence until the next
  scheduled date starts. Notification readers may resolve a separate future
  occurrence so they never schedule a reminder in the past.
- The recurrence anchor day is stable. A monthly series anchored on day 31
  clamps February to day 28 and returns to day 31 in March.
- A completion records the scheduled calendar identity and the actual UTC
  completion instant separately. Consecutive early completions are allowed.
- All-day schedule identity uses the calendar date. Timed schedule identity
  uses wall-clock components without a timezone offset.
- Date arithmetic remains pure and receives an explicit evaluation time where
  the rule depends on the clock.
- A small domain seam may own current-occurrence resolution and completion
  transition results. The result must expose the scheduled occurrence,
  completion time, and next due date without knowing about JSON or Drift.
- The editor adapts that result into a canonical REST/OT document operation.
  Relational task and completion data remain projections of that document.
- No independent task-occurrence table or direct task mutation path is added.

## Boundaries

This decision does not require moving every recurrence helper into one large
class. `nextDueDate` and related date calculations can remain focused pure
functions. Serialization of task metadata remains at the editor/document
boundary, and persistence remains at the existing projection boundary.

## Consequences

Positive consequences:

- The meaning of “current occurrence” has one domain contract.
- Tests can use a fixed clock and cover time-based behavior deterministically.
- Editor mutations and relational projections can share the same transition
  semantics without sharing persistence code.

Trade-offs:

- Existing behavior needs characterization tests before the seam is changed.
- Time zone, all-day, month-end, and missed-occurrence cases remain part of
  the contract and must not be simplified during the refactor.

## Validation

Candidate 03 begins with characterization tests for non-recurring tasks,
daily, weekday, weekly, and monthly recurrence, timed and all-day tasks,
missed occurrences, month-end clamping, and completion metadata. The full
Flutter test suite and focused task/editor tests must pass before behavior is
changed or the refactor is considered complete.
