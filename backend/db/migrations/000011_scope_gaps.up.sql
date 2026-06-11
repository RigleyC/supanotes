BEGIN;

-- ──────────────────────────────────────────────────────────────────
-- 1. tasks: add completed_at + status CHECK
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE tasks
  ADD COLUMN completed_at TIMESTAMPTZ;

ALTER TABLE tasks
  ADD CONSTRAINT chk_tasks_status
  CHECK (status IN ('open', 'in_progress', 'done'));

UPDATE tasks SET status = 'open' WHERE status = 'pending';

-- ──────────────────────────────────────────────────────────────────
-- 2. routines: normalize to days_of_week + time_of_day
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE routines
  ADD COLUMN time_of_day TIME,
  ADD COLUMN days_of_week SMALLINT[];

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
-- 3. telegram_links: add telegram_user_id
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE telegram_links
  ADD COLUMN telegram_user_id BIGINT;

UPDATE telegram_links tl
SET telegram_user_id = tc.telegram_user_id
FROM telegram_chats tc
WHERE tl.chat_id = tc.chat_id AND tl.telegram_user_id IS NULL;

-- ──────────────────────────────────────────────────────────────────
-- 4. note_embeddings: add HNSW index for similarity search
-- ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_note_embeddings_hnsw
  ON note_embeddings USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- ──────────────────────────────────────────────────────────────────
-- 5. note_links: add id primary key
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
-- 6. routine_logs: add telegram_sent_at
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE routine_logs
  ADD COLUMN telegram_sent_at TIMESTAMPTZ;

COMMIT;
