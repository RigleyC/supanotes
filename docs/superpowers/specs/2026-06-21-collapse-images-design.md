# Collapse Images per Note

## Overview
The user wants to toggle the display mode of all images within a note between a "Full Image" and an "Inline Pill" view. This setting applies uniformly to all images in the note, behaving identically to the `hide_completed` toggle. Individual overrides per image have been explicitly rejected by the user to keep the data model simple.

## Architecture

This feature requires a full-stack update to sync a boolean flag (`collapse_images`) from the SQLite local database up to the PostgreSQL backend and back down to other clients.

### 1. Backend (Go + PostgreSQL)
- **Migrations**: Add `collapse_images BOOLEAN NOT NULL DEFAULT false` to the `notes` table.
- **Queries (`sqlc`)**: Update `db/queries/notes.sql` and `db/queries/sync.sql` to include `collapse_images` in `INSERT`, `SELECT`, and `UPDATE` operations.
- **Models**: `CreateNoteRequest`, `UpdateNoteRequest`, and `NoteResponse` in `internal/notes/handler.go` will be updated to include `CollapseImages`.

### 2. Frontend Local DB (Drift + SQLite)
- **Schema**: Update `Note` table in Drift to include `BoolColumn get collapseImages => boolean().withDefault(const Constant(false))()`.
- **Sync Logic**: Update `NoteSyncDto` and `SyncService` to map `collapse_images` to and from JSON.

### 3. Editor & UI (Flutter)
- **Removal of Legacy Logic**: The `view_mode` markdown serialization will be reverted/removed, as well as the 3-dots menu on individual image attachments.
- **Note State**: The `collapse_images` state will be injected into the Editor's component builder.
- **Component Builder**: `_ImageAttachmentWidget` will check the global note state (`collapse_images`) instead of the node's individual state.
- **Toggle Action**: The global "Colapsar/Expandir imagens" toggle will be placed in the Note's primary options menu (where "Ocultar tarefas concluídas" resides).

## Data Flow
When the user toggles "Colapsar imagens":
1. The Flutter UI updates the `Note` in the local Drift database.
2. The UI rebuilds the Editor, and all `ImageAttachmentNode` components re-render as file pills.
3. The background sync worker detects a dirty note, sends a `PATCH` request to `/api/v1/notes/:id` with `{"collapse_images": true}`.
4. The Go backend saves the change to PostgreSQL.
5. Other devices pull the note, receive the flag, and apply the setting globally to their editors.
