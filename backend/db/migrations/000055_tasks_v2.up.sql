BEGIN;

-- The relational task tables created by the early schema were projections of
-- note blocks. Keep them available for an explicit export/retention process;
-- never silently promote those rows into the independent-task resource.
ALTER TABLE IF EXISTS task_completions
  RENAME TO task_completions_legacy_quarantine_v31;
ALTER TABLE IF EXISTS tasks
  RENAME TO tasks_legacy_quarantine_v31;

CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (length(btrim(title)) > 0),
    -- A task's dueDate is a wall-clock value; has_time distinguishes a
    -- calendar day from a timed value. Do not coerce it to a DATE.
    due_date TIMESTAMP WITHOUT TIME ZONE,
    has_time BOOLEAN NOT NULL DEFAULT FALSE,
    recurrence_rule TEXT,
    reminder TEXT,
    completions JSONB NOT NULL DEFAULT '{}'::jsonb
      CHECK (jsonb_typeof(completions) = 'object'),
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    last_completed_at TIMESTAMPTZ,
    revision BIGINT NOT NULL DEFAULT 0 CHECK (revision >= 0),
    schedule_generation BIGINT NOT NULL DEFAULT 0 CHECK (schedule_generation >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_tasks_v2_owner_agenda
  ON tasks(owner_user_id, deleted_at, due_date);
CREATE INDEX idx_tasks_v2_owner_updated
  ON tasks(owner_user_id, updated_at);

CREATE TRIGGER update_tasks_v2_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE task_operations (
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    operation_id UUID NOT NULL,
    payload_hash TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (task_id, operation_id)
);

CREATE UNIQUE INDEX task_operations_operation_id_uq
  ON task_operations(operation_id);

ALTER TABLE sync_changes
  ADD COLUMN task_id UUID;

ALTER TABLE sync_changes
  DROP CONSTRAINT IF EXISTS sync_changes_kind_check;
ALTER TABLE sync_changes
  ADD CONSTRAINT sync_changes_kind_check CHECK (kind IN (
    'note_changed',
    'note_deleted',
    'note_access_changed',
    'note_access_revoked',
    'note_preferences_changed',
    'task_changed',
    'task_deleted'
  ));

CREATE INDEX idx_sync_changes_task
  ON sync_changes(target_user_id, task_id, sequence)
  WHERE task_id IS NOT NULL;

COMMIT;
