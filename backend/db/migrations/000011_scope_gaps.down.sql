BEGIN;

ALTER TABLE routine_logs DROP COLUMN IF EXISTS telegram_sent_at;

ALTER TABLE note_links DROP CONSTRAINT IF EXISTS note_links_pkey;
ALTER TABLE note_links DROP COLUMN IF EXISTS id;

DROP INDEX IF EXISTS idx_note_embeddings_hnsw;

ALTER TABLE telegram_links DROP COLUMN IF EXISTS telegram_user_id;

ALTER TABLE routines DROP COLUMN IF EXISTS days_of_week;
ALTER TABLE routines DROP COLUMN IF EXISTS time_of_day;

ALTER TABLE tasks DROP CONSTRAINT IF EXISTS chk_tasks_status;
ALTER TABLE tasks DROP COLUMN IF EXISTS completed_at;

COMMIT;
