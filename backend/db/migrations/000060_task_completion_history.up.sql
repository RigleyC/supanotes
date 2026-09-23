ALTER TABLE tasks
  ADD COLUMN completion_history JSONB NOT NULL DEFAULT '[]'::jsonb
  CHECK (jsonb_typeof(completion_history) = 'array');
