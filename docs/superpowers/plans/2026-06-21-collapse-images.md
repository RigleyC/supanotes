# Collapse Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a global `collapse_images` toggle per note to view all images as file pills, backed by full-stack sync (SQLite + PostgreSQL).

**Architecture:** A new boolean `collapse_images` will be added to the `notes` table in both the backend and frontend. The markdown-based per-image `view_mode` override introduced previously will be removed to keep data structures simple. The UI will toggle images based on the note's state.

**Tech Stack:** Go, PostgreSQL, sqlc, Flutter, Riverpod, Drift.

---

### Task 1: Backend Database Migration & sqlc

**Files:**
- Create: `backend/db/migrations/000015_add_collapse_images_to_notes.up.sql`
- Create: `backend/db/migrations/000015_add_collapse_images_to_notes.down.sql`
- Modify: `backend/db/queries/notes.sql`
- Modify: `backend/db/queries/sync.sql`

- [ ] **Step 1: Write UP migration**
Create `backend/db/migrations/000015_add_collapse_images_to_notes.up.sql`
```sql
ALTER TABLE notes ADD COLUMN collapse_images BOOLEAN NOT NULL DEFAULT false;
```

- [ ] **Step 2: Write DOWN migration**
Create `backend/db/migrations/000015_add_collapse_images_to_notes.down.sql`
```sql
ALTER TABLE notes DROP COLUMN collapse_images;
```

- [ ] **Step 3: Update `notes.sql` queries**
Modify `backend/db/queries/notes.sql` to include `collapse_images` everywhere `hide_completed` is used.
```sql
-- In CreateNote
INSERT INTO notes (user_id, context_id, content, is_inbox, favorite, archived, embedding_status, hide_completed, collapse_images)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
RETURNING *;

-- In UpdateNote
UPDATE notes SET
    -- ...
    hide_completed = COALESCE(sqlc.narg('hide_completed'), hide_completed),
    collapse_images = COALESCE(sqlc.narg('collapse_images'), collapse_images),
    -- ...
```

- [ ] **Step 4: Update `sync.sql` queries**
Modify `backend/db/queries/sync.sql` to include `collapse_images`.
```sql
-- In UpsertNote
INSERT INTO notes (id, user_id, context_id, content, is_inbox, favorite, archived, embedding_status, hide_completed, collapse_images, created_at, updated_at, deleted_at)
-- ...
ON CONFLICT (id) DO UPDATE SET
    -- ...
    hide_completed = EXCLUDED.hide_completed,
    collapse_images = EXCLUDED.collapse_images,
    -- ...
```

- [ ] **Step 5: Run sqlc**
```bash
cd backend && make generate
```

- [ ] **Step 6: Commit**
```bash
git add backend/db backend/internal/db/sqlcgen
git commit -m "feat(backend): add collapse_images db schema and queries"
```

### Task 2: Backend API & Service Models

**Files:**
- Modify: `backend/internal/notes/handler.go`
- Modify: `backend/internal/notes/service.go`

- [ ] **Step 1: Update API requests & responses**
In `backend/internal/notes/handler.go`, add `CollapseImages` to all models alongside `HideCompleted`:
```go
type CreateNoteRequest struct {
    // ...
    HideCompleted  bool   `json:"hide_completed"`
    CollapseImages bool   `json:"collapse_images"`
}

type UpdateNoteRequest struct {
    // ...
    HideCompleted  *bool  `json:"hide_completed"`
    CollapseImages *bool  `json:"collapse_images"`
}

type NoteResponse struct {
    // ...
    HideCompleted  bool       `json:"hide_completed"`
    CollapseImages bool       `json:"collapse_images"`
}
```

- [ ] **Step 2: Update `service.go` method signatures**
Update `CreateNote` and `UpdateNote` in `backend/internal/notes/service.go` to accept `collapseImages bool` (or `*bool` for update) and pass it to the `sqlcgen` parameters.

- [ ] **Step 3: Update `handler.go` usage**
Pass the `req.CollapseImages` values from the handler to the updated service methods. Also map the returned note's `CollapseImages` to the `NoteResponse`.

- [ ] **Step 4: Commit**
```bash
git add backend/internal/notes
git commit -m "feat(backend): support collapse_images in note API"
```

### Task 3: Frontend Drift Schema

**Files:**
- Modify: `lib/core/database/database.dart`

- [ ] **Step 1: Add column to Note table**
In `lib/core/database/database.dart`, locate the `Notes` table and add:
```dart
  BoolColumn get collapseImages => boolean().withDefault(const Constant(false))();
```

- [ ] **Step 2: Run build_runner**
```bash
dart run build_runner build -d
```

- [ ] **Step 3: Commit**
```bash
git add lib/core/database
git commit -m "feat(app): add collapse_images to local sqlite schema"
```

### Task 4: Frontend Sync & API Models

**Files:**
- Modify: `lib/core/sync/sync_mapper.dart`

- [ ] **Step 1: Map JSON in `sync_mapper.dart`**
Update `noteToJson` and `noteFromJson` to handle `collapse_images`.
```dart
// In noteToJson:
'collapse_images': n.collapseImages,

// In noteFromJson:
collapseImages: (json['collapse_images'] as bool?) ?? false,
```

- [ ] **Step 2: Commit**
```bash
git add lib/core/sync
git commit -m "feat(app): sync collapse_images with backend"
```

### Task 5: Frontend Editor & Revert Legacy Logic

**Files:**
- Modify: `lib/features/notes/domain/attachment_nodes.dart`
- Modify: `lib/features/notes/data/attachment_markdown.dart`
- Modify: `lib/features/notes/presentation/widgets/attachment_components.dart`
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart`

- [ ] **Step 1: Remove `viewMode` from `ImageAttachmentNode`**
In `lib/features/notes/domain/attachment_nodes.dart`, delete the `viewMode` property and constructor argument.

- [ ] **Step 2: Revert markdown serialization**
In `lib/features/notes/data/attachment_markdown.dart`, remove the `if (node.viewMode == 'inline') 'view_mode': 'inline'` logic. Ensure images serialize purely as `{id, url, filename}`.

- [ ] **Step 3: Make components read global note state**
In `lib/features/notes/presentation/widgets/attachment_components.dart`, add `final bool collapseImages;` to `AttachmentComponentBuilder`, `_AttachmentViewModel`, and `_ImageAttachmentWidget`.
In `_ImageAttachmentWidget`, replace `if (node.viewMode == 'inline')` with `if (collapseImages)`.
Remove the `onChangeViewMode` callback and the `PopupMenuButton` from the attachments entirely.

- [ ] **Step 4: Pass state from `NoteEditor`**
In `lib/features/notes/presentation/widgets/note_editor.dart` (or wherever `AttachmentComponentBuilder` is instantiated), pass the active note's `collapseImages` value to the builder:
```dart
AttachmentComponentBuilder(
  editor: editor,
  collapseImages: widget.note.collapseImages,
)
```

- [ ] **Step 5: Add Toggle Action to Note Menu**
In the appropriate top-level widget (e.g., the note screen's app bar actions), add a toggle for "Colapsar imagens" that updates the `note.collapseImages` state and saves it to the local repository.

- [ ] **Step 6: Commit**
```bash
git add lib/features/notes
git commit -m "feat(app): implement global note image collapse toggle and revert individual overrides"
```
