BEGIN;

DO $$
BEGIN
  IF (SELECT COUNT(*) FROM tasks) <> 0
     OR (SELECT COUNT(*) FROM task_operations) <> 0 THEN
    RAISE EXCEPTION
      'cannot roll back tasks_v2 while independent task data exists';
  END IF;

  IF EXISTS (
    SELECT 1 FROM sync_changes
    WHERE kind IN ('task_changed', 'task_deleted')
  ) THEN
    RAISE EXCEPTION
      'cannot roll back tasks_v2 while task feed events exist';
  END IF;
END;
$$;

DROP INDEX IF EXISTS idx_sync_changes_task;
ALTER TABLE sync_changes DROP CONSTRAINT IF EXISTS sync_changes_kind_check;
ALTER TABLE sync_changes DROP COLUMN IF EXISTS task_id;
ALTER TABLE sync_changes
  ADD CONSTRAINT sync_changes_kind_check CHECK (kind IN (
    'note_changed',
    'note_deleted',
    'note_access_changed',
    'note_access_revoked',
    'note_preferences_changed'
  ));

DROP TABLE task_operations;
DROP TABLE tasks;

ALTER TABLE tasks_legacy_quarantine_v31 RENAME TO tasks;
ALTER TABLE task_completions_legacy_quarantine_v31
  RENAME TO task_completions;

COMMIT;
