-- Restore context_id on notes
ALTER TABLE notes ADD COLUMN context_id uuid REFERENCES contexts(id);

-- Restore search/embedding columns
ALTER TABLE notes ADD COLUMN embedding_status text NOT NULL DEFAULT 'pending';
ALTER TABLE notes ADD COLUMN search_vector tsvector;

-- Restore discarded feature tables (structure only, no data)
CREATE TABLE contexts (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), name text NOT NULL, color text, icon text, created_at timestamptz NOT NULL DEFAULT NOW(), updated_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE tags (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), name text NOT NULL, color text, created_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE note_tags (note_id uuid NOT NULL REFERENCES notes(id), tag_id uuid NOT NULL REFERENCES tags(id), PRIMARY KEY (note_id, tag_id));
CREATE TABLE souls (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id) UNIQUE, name text NOT NULL DEFAULT '', bio text NOT NULL DEFAULT '', traits jsonb NOT NULL DEFAULT '{}', communication_style text NOT NULL DEFAULT 'casual', created_at timestamptz NOT NULL DEFAULT NOW(), updated_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE memories (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), content text NOT NULL, embedding vector(1536), created_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE messages (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), role text NOT NULL, content text NOT NULL, tool_calls jsonb, created_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE agent_working_memory (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), content text NOT NULL, priority int NOT NULL DEFAULT 0, expires_at timestamptz, created_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE routines (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), name text NOT NULL, cron_expr text NOT NULL, enabled boolean NOT NULL DEFAULT true, last_run_at timestamptz, created_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE routine_logs (id uuid PRIMARY KEY, routine_id uuid NOT NULL REFERENCES routines(id), status text NOT NULL, output text, created_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE note_yjs_updates (note_id uuid NOT NULL REFERENCES notes(id), update_data bytea NOT NULL, created_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE note_yjs_states (note_id uuid PRIMARY KEY REFERENCES notes(id), state bytea NOT NULL, updated_at timestamptz NOT NULL DEFAULT NOW());
CREATE TABLE pending_tool_confirmations (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), tool_name text NOT NULL, args jsonb NOT NULL, status text NOT NULL DEFAULT 'pending', created_at timestamptz NOT NULL DEFAULT NOW());
