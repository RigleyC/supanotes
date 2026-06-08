-- Better excerpt: 200 chars with markdown stripping
CREATE OR REPLACE FUNCTION notes_excerpt_update() RETURNS trigger AS $$
BEGIN
  NEW.excerpt := substring(
    regexp_replace(NEW.content, '[#*_>`\-]+', '', 'g')
    FROM 1 FOR 200
  );
  RETURN NEW;
END $$ LANGUAGE plpgsql;

-- Partial indexes for performance
CREATE INDEX IF NOT EXISTS notes_active_idx ON notes (user_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS tasks_user_open_idx ON tasks (user_id, due_date) WHERE status = 'open' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS tasks_user_due_idx ON tasks (user_id, due_date) WHERE status = 'open' AND deleted_at IS NULL AND due_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS tasks_active_idx ON tasks (user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS memories_embedding_idx ON memories USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
