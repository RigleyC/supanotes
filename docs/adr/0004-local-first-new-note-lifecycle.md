# 0004: Local-First New Note Lifecycle

## Status

Accepted

## Context

The editor used to open a route with a generated note id and create the database row lazily from the first title or content autosave. That made the editor operate on a phantom id, split title/content persistence into competing paths, and allowed empty notes to be pushed before `flushBeforePop` could clean them up.

The product glossary now treats a New Note as a real Note started by the User, not a separate draft entity. An Empty Note has no meaningful title, body content, tasks, attachments, or tags, and is not shown in regular note lists.

## Decision

When the user starts a new regular note, the Flutter app creates a local Note row immediately and opens the editor for that row. New local notes start without a remote copy. Empty local-only notes are hidden from regular lists, excluded from sync push, and hard-deleted locally when the user leaves the editor empty.

Autosave saves the current Note snapshot locally: title, body content, and extracted tasks. Sync remains asynchronous and pushes only eligible local changes through the existing sync loop.

Notes that already have a remote copy keep using tombstones for deletion.

## Consequences

- The editor always edits a real local Note.
- Tags and tasks can safely attach to a newly created note before the first body edit.
- The backend is protected from empty regular notes.
- The local database needs a local-only marker for whether a note has a remote copy.
- Deletion must choose hard local delete for empty local-only notes and tombstone for remote notes.
