BEGIN;

-- ──────────────────────────────────────────────────────────────────
-- 1. tasks: add completed_at + fix status CHECK to only open|done
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

UPDATE tasks SET status = 'open' WHERE status IN ('pending', 'in_progress');
UPDATE tasks SET status = 'done' WHERE status = 'completed';

ALTER TABLE tasks
  DROP CONSTRAINT IF EXISTS chk_tasks_status;

ALTER TABLE tasks
  ADD CONSTRAINT chk_tasks_status
  CHECK (status IN ('open', 'done'));

-- ──────────────────────────────────────────────────────────────────
-- 2. task_completions: add due_date, drop status column
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE task_completions
  ADD COLUMN IF NOT EXISTS due_date DATE;

ALTER TABLE task_completions
  DROP COLUMN IF EXISTS status;

-- ──────────────────────────────────────────────────────────────────
-- 3. routines: normalize to days_of_week + time_of_day
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE routines
  ADD COLUMN IF NOT EXISTS time_of_day TIME,
  ADD COLUMN IF NOT EXISTS days_of_week SMALLINT[];

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
    ELSE NULL
  END
WHERE cron_expr IS NOT NULL AND time_of_day IS NULL;

-- ──────────────────────────────────────────────────────────────────
-- 4. telegram_links: add telegram_user_id (no telegram_chats dependency)
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE telegram_links
  ADD COLUMN IF NOT EXISTS telegram_user_id BIGINT;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM telegram_links WHERE telegram_user_id IS NULL
  ) THEN
    RAISE NOTICE 'telegram_user_id is NULL for existing rows; relink affected Telegram accounts';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS telegram_links_telegram_user_id_idx
  ON telegram_links (telegram_user_id)
  WHERE telegram_user_id IS NOT NULL;

-- ──────────────────────────────────────────────────────────────────
-- 5. note_embeddings: add HNSW index for similarity search
-- ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_note_embeddings_hnsw
  ON note_embeddings USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- ──────────────────────────────────────────────────────────────────
-- 6. note_links: add id primary key
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE note_links
  ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();

UPDATE note_links SET id = gen_random_uuid() WHERE id IS NULL;

ALTER TABLE note_links
  ALTER COLUMN id SET NOT NULL;

ALTER TABLE note_links
  DROP CONSTRAINT IF EXISTS note_links_pkey;

ALTER TABLE note_links
  ADD PRIMARY KEY (id);

-- ──────────────────────────────────────────────────────────────────
-- 7. routine_logs: add telegram_sent_at
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE routine_logs
  ADD COLUMN telegram_sent_at TIMESTAMPTZ;

COMMIT;
