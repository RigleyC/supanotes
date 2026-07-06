# Remove Braindump Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completely remove the Braindump / Inbox feature across the backend and frontend, including migrating the database schemas, removing API routes, services, handlers, agent tools, and frontend UI components.

**Architecture:** 
- The backend Postgres schema is modified to drop constraints and drop the `is_inbox` column after deleting existing inbox notes.
- Go handlers, service methods, and agent tools related to the inbox/braindump are deleted.
- The frontend Drift database raises its schema version to 15, drops the `is_inbox` column, and regenerates.
- Frontend screens, models, components, routes, and providers associated with the inbox are removed, and references to `isInbox` are cleaned up.

**Tech Stack:** Go, PostgreSQL, SQLC, Flutter, Drift, Riverpod, GoRouter.

---

### Task 1: Backend Database Schema Migration

**Files:**
- Create: `backend/db/migrations/000028_remove_braindump.up.sql`
- Create: `backend/db/migrations/000028_remove_braindump.down.sql`

- [ ] **Step 1: Write Up migration file**
  Create `backend/db/migrations/000028_remove_braindump.up.sql` with the following content:
  ```sql
  -- Remove constraint
  ALTER TABLE notes DROP CONSTRAINT IF EXISTS chk_inbox_not_archived;

  -- Delete all inbox notes and cascade tasks/nodes
  DELETE FROM notes WHERE is_inbox = true;

  -- Drop single inbox index
  DROP INDEX IF EXISTS idx_notes_single_inbox;

  -- Drop is_inbox column
  ALTER TABLE notes DROP COLUMN IF EXISTS is_inbox;
  ```

- [ ] **Step 2: Write Down migration file**
  Create `backend/db/migrations/000028_remove_braindump.down.sql` with the following content:
  ```sql
  -- Re-add is_inbox column
  ALTER TABLE notes ADD COLUMN is_inbox BOOLEAN NOT NULL DEFAULT false;

  -- Re-create unique single inbox index
  CREATE UNIQUE INDEX idx_notes_single_inbox ON notes (user_id) WHERE is_inbox = true AND deleted_at IS NULL;

  -- Re-add constraint
  ALTER TABLE notes ADD CONSTRAINT chk_inbox_not_archived CHECK (is_inbox = false OR archived = false);
  ```

- [ ] **Step 3: Run migrations**
  Run: `go run ./cmd/migrate` in `backend/` directory.
  Expected: Migrations apply successfully.

- [ ] **Step 4: Commit**
  ```bash
  git add backend/db/migrations/000028_remove_braindump.*
  git commit -m "migration(db): add 000028_remove_braindump migration"
  ```

---

### Task 2: Update SQLC Queries and Regenerate SQLC

**Files:**
- Modify: `backend/db/queries/notes.sql`
- Modify: `backend/db/queries/ai.sql`
- Modify: `backend/db/queries/search.sql`
- Modify: `backend/db/queries/sync.sql`

- [ ] **Step 1: Edit notes.sql**
  - Delete queries: `GetInboxNote`, `AppendToInbox`, and `SetInboxContent`.
  - In `CreateNote` query, remove `is_inbox` from columns and values.
  - In all other queries, remove filters checking `is_inbox = false` or `NOT is_inbox`.
  Specifically, edit `backend/db/queries/notes.sql` to match:
  ```sql
  -- name: CreateNote :one
  INSERT INTO notes (user_id, context_id, content, embedding_status, collapse_images)
  VALUES ($1, $2, $3, $4, $5)
  RETURNING *;

  -- name: GetNotes :many
  SELECT n.*,
    COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title,
    COALESCE(unp.favorite, FALSE)::boolean AS favorite,
    COALESCE(unp.archived, FALSE)::boolean AS archived
  FROM notes n
  LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $1
  WHERE n.deleted_at IS NULL
    AND (n.user_id = $1 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = n.id AND note_shares.user_id = $1))
    AND (sqlc.narg('context_id')::uuid IS NULL OR n.context_id = sqlc.narg('context_id'))
    AND (sqlc.narg('favorite')::boolean IS NULL OR COALESCE(unp.favorite, FALSE) = sqlc.narg('favorite'))
    AND (sqlc.narg('cursor_updated_at')::timestamptz IS NULL OR n.updated_at < sqlc.narg('cursor_updated_at') OR (n.updated_at = sqlc.narg('cursor_updated_at') AND n.id < sqlc.narg('cursor_id')))
  ORDER BY n.updated_at DESC, n.id DESC
  LIMIT sqlc.arg('limit');

  -- name: GetRecentNotes :many
  SELECT n.*,
    COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title,
    COALESCE(unp.favorite, FALSE)::boolean AS favorite,
    COALESCE(unp.archived, FALSE)::boolean AS archived
  FROM notes n
  LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $1
  WHERE n.user_id = $1
    AND n.deleted_at IS NULL
    AND n.updated_at >= NOW() - INTERVAL '48 hours'
  ORDER BY n.updated_at DESC
  LIMIT 10;

  -- name: GetLinkedNotes :many
  SELECT DISTINCT n.* FROM notes n
  JOIN note_links nl ON (n.id = nl.source_id OR n.id = nl.target_id)
  WHERE (nl.source_id = ANY($1::uuid[]) OR nl.target_id = ANY($1::uuid[]))
    AND n.id != ALL($1::uuid[])
    AND n.user_id = $2
    AND n.deleted_at IS NULL
  LIMIT 5;

  -- name: AppendToNoteContent :one
  UPDATE notes
  SET content = content || E'\n\n' || $3, updated_at = NOW()
  WHERE notes.id = $1 AND notes.deleted_at IS NULL
    AND (notes.user_id = $2 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = $1 AND note_shares.user_id = $2 AND note_shares.permission = 'edit'))
  RETURNING *;

  -- name: CountNotes :one
  SELECT COUNT(*) FROM notes WHERE user_id = $1 AND deleted_at IS NULL;
  ```

- [ ] **Step 2: Edit ai.sql**
  Update `backend/db/queries/ai.sql` to remove `is_inbox` filters:
  ```sql
  -- name: GetRetryableEmbeddings :many
  SELECT n.id, n.content, n.user_id 
  FROM notes n
  WHERE (n.embedding_status = 'pending'
     OR (n.embedding_status = 'failed' AND n.updated_at < NOW() - INTERVAL '5 minutes'))
    AND n.deleted_at IS NULL
  LIMIT $1;

  -- name: SearchNotesByEmbedding :many
  SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.updated_at, (1 - (ne.embedding <=> $2::vector))::real AS similarity
  FROM notes n
  JOIN note_embeddings ne ON n.id = ne.note_id
  WHERE n.user_id = $1 AND n.deleted_at IS NULL
  ORDER BY ne.embedding <=> $2::vector
  LIMIT $3;
  ```

- [ ] **Step 3: Edit search.sql**
  Update `backend/db/queries/search.sql` to remove `is_inbox` filters:
  ```sql
  -- name: SearchNotesFTS :many
  SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
         COALESCE(unp.favorite, FALSE) AS favorite,
         COALESCE(unp.archived, FALSE) AS archived,
         ts_rank(n.search_vector, plainto_tsquery('simple', sqlc.arg('query')::text)) AS score
  FROM notes n
  LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
  WHERE n.user_id = sqlc.arg('user_id')
    AND n.deleted_at IS NULL 
    AND COALESCE(unp.archived, FALSE) = false
    AND n.search_vector @@ plainto_tsquery('simple', sqlc.arg('query')::text)
  ORDER BY score DESC
  LIMIT sqlc.arg('limit');

  -- name: SearchNotesSemantic :many
  SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
         COALESCE(unp.favorite, FALSE) AS favorite,
         COALESCE(unp.archived, FALSE) AS archived,
         (1.0 - (ne.embedding <=> sqlc.arg('embedding')::vector))::float8 AS score
  FROM notes n
  JOIN note_embeddings ne ON n.id = ne.note_id
  LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
  WHERE n.user_id = sqlc.arg('user_id')
    AND n.deleted_at IS NULL 
    AND COALESCE(unp.archived, FALSE) = false
  ORDER BY ne.embedding <=> sqlc.arg('embedding')::vector
  LIMIT sqlc.arg('limit');

  -- name: SearchNotesHybrid :many
  WITH fts AS (
    SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
           COALESCE(unp.favorite, FALSE) AS favorite,
           COALESCE(unp.archived, FALSE) AS archived,
           row_number() OVER (ORDER BY ts_rank(n.search_vector, to_tsquery('simple', sqlc.arg('query')::text)) DESC) as rank
    FROM notes n
    LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
    WHERE n.user_id = sqlc.arg('user_id')
      AND n.deleted_at IS NULL 
      AND COALESCE(unp.archived, FALSE) = false
      AND n.search_vector @@ to_tsquery('simple', sqlc.arg('query')::text)
    LIMIT sqlc.arg('fts_limit')::int
  ),
  semantic AS (
    SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
           COALESCE(unp.favorite, FALSE) AS favorite,
           COALESCE(unp.archived, FALSE) AS archived,
           row_number() OVER (ORDER BY ne.embedding <=> sqlc.arg('embedding')::vector) as rank
    FROM notes n
    JOIN note_embeddings ne ON n.id = ne.note_id
    LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
    WHERE n.user_id = sqlc.arg('user_id')
      AND n.deleted_at IS NULL 
      AND COALESCE(unp.archived, FALSE) = false
    LIMIT sqlc.arg('semantic_limit')::int
  )
  SELECT 
    COALESCE(fts.id, semantic.id) as id,
    COALESCE(fts.title, semantic.title) as title,
    COALESCE(fts.content, semantic.content) as content,
    COALESCE(fts.excerpt, semantic.excerpt) as excerpt,
    COALESCE(fts.updated_at, semantic.updated_at) as updated_at,
    COALESCE(fts.context_id, semantic.context_id) as context_id,
    COALESCE(fts.favorite, semantic.favorite) as favorite,
    COALESCE(fts.archived, semantic.archived) as archived,
    (COALESCE(1.0 / (60.0 + fts.rank), 0.0) + COALESCE(1.0 / (60.0 + semantic.rank), 0.0))::float8 AS score
  FROM fts
  FULL OUTER JOIN semantic ON fts.id = semantic.id
  ORDER BY score DESC
  LIMIT sqlc.arg('limit')::int;
  ```

- [ ] **Step 4: Edit sync.sql**
  Update `backend/db/queries/sync.sql` to remove references to `is_inbox`:
  ```sql
  -- name: UpsertNote :one
  INSERT INTO notes (id, user_id, context_id, content, embedding_status, collapse_images, created_at, updated_at, deleted_at)
  VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $8)
  ON CONFLICT (id) DO UPDATE
  SET context_id = EXCLUDED.context_id,
      content = EXCLUDED.content,
      embedding_status = EXCLUDED.embedding_status,
      collapse_images = EXCLUDED.collapse_images,
      updated_at = NOW(),
      deleted_at = EXCLUDED.deleted_at
  WHERE notes.user_id = EXCLUDED.user_id
  RETURNING *;
  ```

- [ ] **Step 5: Regenerate SQLC**
  Run: `make sqlc` or `sqlc generate` in `backend/` directory.
  Expected: SQLC regenerates models and queries without error.

- [ ] **Step 6: Commit**
  ```bash
  git add backend/db/queries/*.sql backend/internal/db/sqlcgen/
  git commit -m "feat(sqlc): remove is_inbox references and regenerate SQLC code"
  ```

---

### Task 3: Backend Business Logic and Handler Clean-up

**Files:**
- Modify: `backend/internal/notes/service.go`
- Modify: `backend/internal/notes/repository.go`
- Modify: `backend/internal/notes/handler.go`
- Modify: `backend/cmd/server/main.go`
- Modify: `backend/internal/notes/service_test.go`

- [ ] **Step 1: Clean up notes/repository.go**
  - Remove interface definitions and implementations for: `GetInboxNote`, `AppendToInbox`, `SetInboxContent`.

- [ ] **Step 2: Clean up notes/service.go**
  - Delete `ErrInboxRule`.
  - In `CreateNote`, remove checks on `note.IsInbox` that throw `ErrInboxRule` (if any).
  - Delete `GetInboxNote`, `SetInboxContent`, `AppendToInbox`, `PlanInboxOrganization`, and `ApplyOrganization`.
  - Fix batch insertions to omit `is_inbox` column / value.

- [ ] **Step 3: Clean up notes/service_test.go**
  - Delete mock implementation methods for `GetInboxNote`, `AppendToInbox`, and `SetInboxContent`.

- [ ] **Step 4: Clean up notes/handler.go**
  - Remove handlers: `GetInbox`, `AppendToInbox`, `PlanOrganization`, `ApplyOrganization`.
  - Remove request schemas like `AppendToInboxRequest`.
  - Remove field `IsInbox` from `NoteResponse`.
  - Remove references to `ErrInboxRule`.

- [ ] **Step 5: Clean up cmd/server/main.go**
  - Remove router lines:
    ```go
    protected.GET("/notes/inbox", notesH.GetInbox)
    protected.POST("/notes/inbox/append", notesH.AppendToInbox)
    protected.POST("/notes/inbox/organize/plan", notesH.PlanOrganization)
    protected.POST("/notes/inbox/organize/apply", notesH.ApplyOrganization)
    ```

- [ ] **Step 6: Run Go Tests**
  Run: `go test ./internal/notes/...`
  Expected: PASS

- [ ] **Step 7: Commit**
  ```bash
  git add backend/internal/notes/ backend/cmd/server/
  git commit -m "cleanup(backend): remove inbox routes, handlers, repository methods, and tests"
  ```

---

### Task 4: AI Agent Loop and Registry Updates

**Files:**
- Modify: `backend/pkg/llm/factory.go`
- Modify: `backend/internal/agent/loop.go`
- Modify: `backend/internal/agent/context.go`
- Modify: `backend/internal/agent/tools/registry.go`
- Delete: `backend/internal/agent/tools/notes_tools.go:GetInboxNoteTool`, `AppendToInboxTool`, `PlanInboxOrganizationTool`, `ApplyInboxOrganizationTool`

- [ ] **Step 1: Rename LLM Task Type**
  In `backend/pkg/llm/factory.go`:
  - Rename `TaskTypeInboxOrganize` to `TaskTypeAgentHelper`.
  - Update comments and fields accordingly.

- [ ] **Step 2: Update Agent Loop and Context**
  In `backend/internal/agent/loop.go`:
  - Update `llm.TaskTypeInboxOrganize` references to `llm.TaskTypeAgentHelper`.
  In `backend/internal/agent/context.go`:
  - Remove counting and context inclusion logic checking for `IsInbox`.

- [ ] **Step 3: Delete Agent Inbox Tools**
  In `backend/internal/agent/tools/notes_tools.go`:
  - Delete `GetInboxNoteTool` class and methods.
  - Delete `AppendToInboxTool` class and methods.
  - Delete `PlanInboxOrganizationTool` class and methods.
  - Delete `ApplyInboxOrganizationTool` class and methods.

- [ ] **Step 4: Update Tools Registry**
  In `backend/internal/agent/tools/registry.go`:
  - Remove registry instantiations: `&GetInboxNoteTool{...}`, `&AppendToInboxTool{...}`, `&PlanInboxOrganizationTool{...}`, `&ApplyInboxOrganizationTool{...}`.
  - Remove risk classifications for `get_inbox_note`, `plan_inbox_organization`, `append_to_inbox`, `apply_inbox_organization`.

- [ ] **Step 5: Run Agent Tests**
  Run: `go test ./internal/agent/...`
  Expected: PASS

- [ ] **Step 6: Commit**
  ```bash
  git add backend/pkg/llm/ backend/internal/agent/
  git commit -m "cleanup(agent): remove inbox agent tools and update loop model task type"
  ```

---

### Task 5: Frontend Database Schema and DAO Migration

**Files:**
- Modify: `lib/core/database/tables/notes.dart`
- Modify: `lib/core/database/database.dart`
- Modify: `lib/core/database/daos/notes_dao.dart`
- Modify: `lib/core/sync/sync_mapper.dart`

- [ ] **Step 1: Modify Table Schema**
  In `lib/core/database/tables/notes.dart`:
  - Delete line: `BoolColumn get isInbox => boolean().withDefault(const Constant(false))();`

- [ ] **Step 2: Bump Schema and Add Migration**
  In `lib/core/database/database.dart`:
  - Increment `schemaVersion` to `15`.
  - In `onUpgrade`, add logic for migration version 15:
    ```dart
    if (from < 15) {
      await customStatement('DELETE FROM notes WHERE is_inbox = 1;');
      await customStatement('ALTER TABLE notes DROP COLUMN is_inbox;');
    }
    ```

- [ ] **Step 3: Modify Notes DAO**
  In `lib/core/database/daos/notes_dao.dart`:
  - Remove methods `getInboxNote` and `watchInboxNote`.
  - Remove `isInbox: row.read<bool>('is_inbox'),` mapping in `_queryResultFromRow`.
  - Remove `t.isInbox.equals(true) |` line from `getDirtyNotes`.
  - Update `watchAllActiveNotes` to remove `AND n.is_inbox = 0` condition from query.

- [ ] **Step 4: Modify Sync Mapper**
  In `lib/core/sync/sync_mapper.dart`:
  - Remove `'is_inbox': n.isInbox,` from `noteToJson`.
  - Remove `isInbox: (json['is_inbox'] as bool?) ?? false,` from `noteFromJson`.

- [ ] **Step 5: Regenerate Drift Database Code**
  Run: `flutter pub run build_runner build --delete-conflicting-outputs`
  Expected: Regenerates `database.g.dart` successfully.

- [ ] **Step 6: Commit**
  ```bash
  git add lib/core/database/ lib/core/sync/
  git commit -m "feat(drift): drop isInbox column from Notes table, update DAO, mapper, and regenerate code"
  ```

---

### Task 6: Remove Frontend Screen and UI Code

**Files:**
- Delete: `lib/features/notes/presentation/inbox_screen.dart`
- Delete: `lib/features/notes/presentation/widgets/inbox_organize_sheet.dart`
- Delete: `lib/features/notes/presentation/widgets/brain_dump_tile.dart`
- Delete: `lib/features/agent/data/inbox_organize_repository.dart`
- Delete: `lib/features/agent/domain/organization_plan.dart`
- Delete: `lib/features/agent/domain/destination_type.dart`
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/core/router/app_routes.dart`
- Modify: `lib/features/notes/data/notes_repository.dart`
- Modify: `lib/features/notes/data/local/notes_local_repository.dart`
- Modify: `lib/features/notes/domain/note_model.dart`
- Modify: `lib/features/notes/presentation/controllers/notes_providers.dart`

- [ ] **Step 1: Delete Files**
  Run:
  ```powershell
  Remove-Item lib/features/notes/presentation/inbox_screen.dart
  Remove-Item lib/features/notes/presentation/widgets/inbox_organize_sheet.dart
  Remove-Item lib/features/notes/presentation/widgets/brain_dump_tile.dart
  Remove-Item lib/features/agent/data/inbox_organize_repository.dart
  Remove-Item lib/features/agent/domain/organization_plan.dart
  Remove-Item lib/features/agent/domain/destination_type.dart
  ```

- [ ] **Step 2: Update Notes List Screen**
  In `lib/features/notes/presentation/notes_list_screen.dart`:
  - Remove imports of `BrainDumpTile`.
  - Remove `BrainDumpTile` widget instantiation from `headerSlivers`.

- [ ] **Step 3: Update App Router**
  In `lib/core/router/app_routes.dart`:
  - Delete `static const inbox = '/inbox';`.
  In `lib/core/router/app_router.dart`:
  - Remove `GoRoute(path: AppRoutes.inbox, builder: (_, _) => const InboxScreen()),`.
  - Remove import of `InboxScreen`.

- [ ] **Step 4: Update Note Model**
  In `lib/features/notes/domain/note_model.dart`:
  - Remove `isInbox` field, parameter, `copyWith` mapping, and factory mapping.

- [ ] **Step 5: Clean up Repositories and Providers**
  In `lib/features/notes/data/local/notes_local_repository.dart`:
  - Remove `watchInbox` and `getOrCreateInboxNote`.
  In `lib/features/notes/data/notes_repository.dart`:
  - Remove `watchInbox`, `ensureInbox`, `appendToInbox`.
  In `lib/features/notes/presentation/controllers/notes_providers.dart`:
  - Delete `inboxProvider`.

- [ ] **Step 6: Run Flutter Tests**
  Run: `flutter test`
  Expected: PASS

- [ ] **Step 7: Commit**
  ```bash
  git add lib/
  git commit -m "cleanup(frontend): remove inbox screens, components, domain files, repositories, and routes"
  ```
