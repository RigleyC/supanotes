# Per-Note Preference Synchronization Design

**Date:** 2026-08-14  
**Status:** Proposed

## Goal

Synchronize each user's per-note preferences across that user's devices while
keeping note content and preferences independent.

The preferences are `favorite`, `archived`, `hide_completed`, and
`collapse_images`.

## Product Rules

- A preference belongs to one `(user_id, note_id)` pair.
- A user can change their preference on a note they can read.
- A user's preference does not change another user's view of the same shared
  note.
- Preference changes made while offline persist locally and are sent after
  connectivity returns.
- The last confirmed write wins when two devices of the same user change the
  same preference row.
- The canonical REST/OT document does not contain preferences.

## Data Ownership

`notes.document` remains the canonical source for note content and task
metadata. `user_note_preferences` is the source for the four visual and
organization preferences above.

`collapse_images` moves from `notes` to `user_note_preferences`. It is no
longer shared note metadata. The migration seeds the owner's preference from
the existing `notes.collapse_images` value, then removes that column and its
frontend projection.

The local Drift preference row keeps `is_dirty`. It is an offline outbox flag,
not a server field:

1. A local write updates the whole preference row and sets `is_dirty`.
2. The catalog sync sends the row to the backend.
3. Only a successful response for the same local `updated_at` clears the flag.
4. A remote preference never overwrites a dirty local row.

## HTTP Contract

Add one authenticated endpoint:

`PATCH /api/v1/notes/:id/preferences`

The request accepts the complete preference row:

```json
{
  "favorite": true,
  "archived": false,
  "hide_completed": true,
  "collapse_images": false
}
```

The server authorizes access to the note, upserts the row under the
authenticated `user_id`, updates server `updated_at`, and returns the saved
preference. It never updates `notes.updated_at` and it accepts no target user
ID.

`GET /api/v1/notes` and `GET /api/v1/notes/:id` return all four values for the
authenticated user. The existing catalog loop lists all accessible notes on
each cycle, so it receives preference changes from another device without a
new preference cursor or a second pull endpoint.

## Sync Flow

`NoteCatalogSync` owns preference synchronization because it already owns
catalog push and pull. It remains separate from `NoteSyncSession` and REST/OT
operations.

Each cycle runs in this order:

1. Send dirty preference rows with the preference endpoint.
2. Pull the remote note catalog.
3. Apply returned preferences only to local rows that are not dirty.

Per-note work uses the existing keyed queue. A failed preference request leaves
the local row dirty for a later cycle. A successful response clears the dirty
flag only when the stored local timestamp still equals the sent timestamp; a
newer local edit remains pending.

## Backend Schema and Authorization

The existing PostgreSQL `user_note_preferences` table gains
`collapse_images BOOLEAN NOT NULL DEFAULT FALSE`. Its primary key stays
`(user_id, note_id)` and its `updated_at` is refreshed on every upsert.

The migration copies `notes.collapse_images` to the note owner's preference
row, creates a row when needed, and drops `notes.collapse_images`. The
corresponding down migration restores the owner value before dropping the
preference column.

The endpoint authorizes the authenticated user with the same access rule as
catalog reads: note owner or an existing `note_shares` row. Read-only sharing
is sufficient because the preference only changes the caller's own row.

## Frontend Persistence and UI

The Drift `UserNotePreferences` table gains `collapseImages`; the `Notes`
table loses `collapseImages`. Its schema migration copies each existing local
note's value to its owner's preference row before dropping the column.

The preference DAO supplies one complete-row local mutation API. Favorite,
archive, hide-completed, and collapse-images UI actions call it. The existing
mutation controller retains optimistic updates and rollback semantics for
network-independent local writes. The catalog sync, rather than a widget,
performs network retry.

## Verification

- Backend handler and service tests: owner, reader, unauthorized caller,
  complete-row upsert, and returned values.
- Backend query tests: catalog and single-note responses contain all four
  preferences for the authenticated user.
- Flutter DAO tests: local change marks dirty; accepted synchronized value
  clears only the matching write; remote data does not overwrite a dirty row.
- Flutter catalog-sync tests: dirty row is pushed; server response clears it;
  remote row is applied on a second device; failed request remains pending.
- Migration tests: backend and Drift preserve the existing collapse-images
  setting for the note owner.
- Manual check: two devices of one user converge after reconnecting; a second
  user on a shared note keeps independent settings.

## Out of Scope

- No preference fields are added to REST/OT operations or `notes.document`.
- No global `user_settings.preferences` data is used for note-specific state.
- No new package, generic synchronization framework, or compatibility path is
  introduced.
