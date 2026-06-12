# Scope Gaps — Part 1: Database Migrations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all database schema gaps discovered in the scope v3 gap analysis. This migration normalizes routines, adds missing columns, and fixes indexes.

**Architecture:** Single migration `000011` with atomic changes. Each task is a separate logical step within the migration.

**Tech Stack:** PostgreSQL 15, pgvector.

**Depends on:** Migration `000010` (from `back-support` plan — note_links relation + CHECK constraint).

---

## File Map

| File | Role | Action |
|------|------|--------|
| `backend/db/migrations/000011_scope_gaps.up.sql` | Migration up | Create |
| `backend/db/migrations/000011_scope_gaps.down.sql` | Migration down | Create |

---

## Task 1: Create migration `000011_scope_gaps.up.sql`

**Why:** 7 schema gaps block documented features: tasks missing `completed_at`, routines using wrong schema, telegram_links missing user ID, note_embeddings missing ivfflat index, note_links missing PK, routine_logs missing `telegram_sent_at`.

---

- [ ] **Step 1: Create up migration**

`backend/db/migrations/000011_scope_gaps.up.sql`:

```sql
BEGIN;

-- ──────────────────────────────────────────────────────────────────
-- 1. tasks: add completed_at + status CHECK
-- ──────────────────────────────────────────────────────────────────
-- Scope §6.1.3: "completed_at: timestamp (auto-set when completed)"
-- Current DB: column does not exist. Flutter sets it locally but backend ignores it.

ALTER TABLE tasks
  ADD COLUMN completed_at TIMESTAMPTZ;

-- Scope §6.1.3: status ∈ {open, in_progress, done}
-- Current DB: text with no constraint. Flutter uses 'pending' (mismatch).

ALTER TABLE tasks
  ADD CONSTRAINT chk_tasks_status
  CHECK (status IN ('open', 'in_progress', 'done'));

-- Backfill existing 'pending' rows to 'open' so the CHECK doesn't fail
UPDATE tasks SET status = 'open' WHERE status = 'pending';

-- ──────────────────────────────────────────────────────────────────
-- 2. routines: normalize to days_of_week + time_of_day
-- ──────────────────────────────────────────────────────────────────
-- Scope §6.1.7: {type, time_of_day, days_of_week, timezone, ...}
-- Current DB: cron_expr (cron string). Scope wants explicit fields.

ALTER TABLE routines
  ADD COLUMN time_of_day TIME,
  ADD COLUMN days_of_week SMALLINT[];  -- 0=Sun..6=Sat, per Dart DateTime.weekday

-- Backfill from cron_expr where possible (best-effort)
-- Pattern: "0 8 * * 1-5" → time_of_day='08:00', days_of_week={1,2,3,4,5}
UPDATE routines SET
  time_of_day = make_time(
    CAST(split_part(cron_expr, ' ', 2) AS INT),
    CAST(split_part(cron_expr, ' ', 1) AS INT),
    0
  ),
  days_of_week = CASE
    WHEN cron_expr ~ '\* \* \* \*' THEN '{0,1,2,3,4,5,6}'::SMALLINT[]
    WHEN cron_expr ~ '1-5' THEN '{1,2,3,4,5}'::SMALLINT[]
    WHEN cron_expr ~ '0,6' THEN '{0,6}'::SMALLINT[]
    ELSE NULL  -- can't parse — leave NULL for manual fixup
  END
WHERE cron_expr IS NOT NULL AND time_of_day IS NULL;

-- Keep cron_expr as legacy column (don't drop yet — runner may still reference it)

-- ──────────────────────────────────────────────────────────────────
-- 3. telegram_links: add telegram_user_id
-- ──────────────────────────────────────────────────────────────────
-- Scope §6.1.9: {telegram_user_id: BIGINT}
-- Current DB: only has chat_id (BIGINT). Missing the user's Telegram user ID.

ALTER TABLE telegram_links
  ADD COLUMN telegram_user_id BIGINT;

-- Backfill from chats table if possible
UPDATE telegram_links tl
SET telegram_user_id = tc.telegram_user_id
FROM telegram_chats tc
WHERE tl.chat_id = tc.chat_id AND tl.telegram_user_id IS NULL;

-- ──────────────────────────────────────────────────────────────────
-- 4. note_embeddings: add ivfflat index
-- ──────────────────────────────────────────────────────────────────
-- Scope §6.2.3: "ivfflat or HNSW index for similarity search"
-- Current DB: no index. Full table scan on every RAG query.

-- NOTE: ivfflat requires at least 100 rows for training. Use HNSW as fallback
-- if the table is small. HNSW is also faster for reads.
CREATE INDEX idx_note_embeddings_hnsw
  ON note_embeddings USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- ──────────────────────────────────────────────────────────────────
-- 5. note_links: add id primary key
-- ──────────────────────────────────────────────────────────────────
-- Scope §6.1.10: {id, source_id, target_id, ...}
-- Current DB: composite PK (source_id, target_id). Scope says id should be PK.

ALTER TABLE note_links
  ADD COLUMN id UUID DEFAULT gen_random_uuid();

UPDATE note_links SET id = gen_random_uuid() WHERE id IS NULL;

ALTER TABLE note_links
  ALTER COLUMN id SET NOT NULL;

-- Drop old composite PK, add new single-column PK
ALTER TABLE note_links
  DROP CONSTRAINT IF EXISTS note_links_pkey;

ALTER TABLE note_links
  ADD PRIMARY KEY (id);

-- Keep unique constraint on (source_id, target_id) to prevent duplicates
-- (it was the old PK, now becomes a unique index)
-- This is already handled if the old PK constraint was named — check schema.
-- If not, add it:
-- ALTER TABLE note_links ADD CONSTRAINT uq_note_links_pair UNIQUE (source_id, target_id);

-- ──────────────────────────────────────────────────────────────────
-- 6. routine_logs: add telegram_sent_at
-- ──────────────────────────────────────────────────────────────────
-- Scope §6.1.8: {telegram_sent_at: timestamp}
-- Current DB: no such column. Cannot track when Telegram notification was sent.

ALTER TABLE routine_logs
  ADD COLUMN telegram_sent_at TIMESTAMPTZ;

COMMIT;
```

---

- [ ] **Step 2: Create down migration**

`backend/db/migrations/000011_scope_gaps.down.sql`:

```sql
BEGIN;

ALTER TABLE routine_logs DROP COLUMN IF EXISTS telegram_sent_at;

ALTER TABLE note_links DROP CONSTRAINT IF EXISTS note_links_pkey;
-- Restore composite PK (best-effort — original constraint name may vary)
-- ALTER TABLE note_links ADD PRIMARY KEY (source_id, target_id);
ALTER TABLE note_links DROP COLUMN IF EXISTS id;

DROP INDEX IF EXISTS idx_note_embeddings_hnsw;

ALTER TABLE telegram_links DROP COLUMN IF EXISTS telegram_user_id;

ALTER TABLE routines DROP COLUMN IF EXISTS days_of_week;
ALTER TABLE routines DROP COLUMN IF EXISTS time_of_day;

ALTER TABLE tasks DROP CONSTRAINT IF EXISTS chk_tasks_status;
ALTER TABLE tasks DROP COLUMN IF EXISTS completed_at;

COMMIT;
```

---

- [ ] **Step 3: Commit**

```bash
git add backend/db/migrations/000011_scope_gaps.up.sql backend/db/migrations/000011_scope_gaps.down.sql
git commit -m "feat(db): migration 000011 — tasks completed_at, routines normalization, telegram_user_id, hnsw index, note_links PK, routine_logs telegram_sent_at"
```

---

## Task 2: Fix task status mismatch in Drift schema

**Why:** DB will now enforce `status IN ('open', 'in_progress', 'done')` but Flutter uses `'pending'` everywhere. This task aligns the Flutter side.

**Files:**
- Modify: `lib/core/database/tables/tasks.dart`
- Modify: `lib/features/tasks/data/local/tasks_local_repository.dart`
- Modify: `lib/features/tasks/presentation/controllers/task_controller.dart`

---

- [ ] **Step 1: Update Drift `Tasks` table status default**

In `lib/core/database/tables/tasks.dart`, change any hardcoded `'pending'` defaults to `'open'`:

```dart
// Before:
TextColumn get status => text().withDefault(const Constant('pending'))();

// After:
TextColumn get status => text().withDefault(const Constant('open'))();
```

---

- [ ] **Step 2: Update all `status: 'pending'` references in `tasks_dao.dart`**

In `lib/core/database/daos/tasks_dao.dart`:

```dart
// Line 45: watchOpenTasks filter
..where((t) => t.status.equals('open'))  // was 'pending'

// Line 125: completeTask — status on completed row
status: const Value('done'),  // already correct

// Line 153: next occurrence for recurring task
status: 'open',  // was 'pending'

// Line 193: reopenTask
status: const Value('open'),  // was 'pending'
```

---

- [ ] **Step 3: Update `task_controller.dart`**

In `lib/features/tasks/presentation/controllers/task_controller.dart`:

```dart
// wherever task.status == 'pending' is checked
// change to task.status == 'open'
```

---

- [ ] **Step 4: Run analysis**

```bash
cd lib && flutter analyze --no-pub 2>&1 | head -20
```

Expected: 0 errors in changed files.

---

- [ ] **Step 5: Commit**

```bash
git add lib/core/database/tables/tasks.dart lib/core/database/daos/tasks_dao.dart lib/features/tasks/presentation/controllers/task_controller.dart
git commit -m "fix(tasks): align Flutter status values with DB CHECK (pending→open)"
```

---

## Task 3: Write `completed_at` on task completion

**Why:** Backend returns `completed_at` in TaskResponse but Flutter never writes it locally on completion.

**Files:**
- Modify: `lib/core/database/daos/tasks_dao.dart`

---

- [ ] **Step 1: Set `completedAt` in `completeTask`**

In `lib/core/database/daos/tasks_dao.dart`, inside the `completeTask` transaction:

```dart
// Line ~123: the update that marks status='done'
await (update(tasks)..where((t) => t.id.equals(id))).write(
  TasksCompanion(
    status: const Value('done'),
    completedAt: Value(now),  // ADD THIS LINE
    updatedAt: Value(now),
    isDirty: const Value(true),
  ),
);
```

---

- [ ] **Step 2: Clear `completedAt` in `reopenTask`**

In `reopenTask` (line ~192), the `completedAt: const Value(null)` is already there. Verify it's correct.

---

- [ ] **Step 3: Commit**

```bash
git add lib/core/database/daos/tasks_dao.dart
git commit -m "fix(tasks): persist completedAt locally on task completion"
```

---

## Self-Review

| Gap | Task | Covered? |
|-----|------|----------|
| tasks.completed_at column | Task 1 + Task 3 | ✅ |
| tasks.status CHECK | Task 1 + Task 2 | ✅ |
| routines days_of_week+time_of_day | Task 1 | ✅ |
| telegram_links.telegram_user_id | Task 1 | ✅ |
| note_embeddings ivfflat/HNSW index | Task 1 | ✅ |
| note_links.id PK | Task 1 | ✅ |
| routine_logs.telegram_sent_at | Task 1 | ✅ |
| Flutter status mismatch (pending→open) | Task 2 | ✅ |
| completed_at not written locally | Task 3 | ✅ |

**Not addressed:** Routines `cron_expr` column kept as legacy (runner migration is in `back-support` plan Task 2). `days_of_week` backfill is best-effort.

---

## Execution Handoff

Plan complete. Ready to execute via subagent-driven or inline approach.
