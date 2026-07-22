-- Drop foreign key from notes.context_id to contexts
ALTER TABLE notes DROP CONSTRAINT IF EXISTS notes_context_id_fkey;

-- Drop discarded feature tables
DROP TABLE IF EXISTS pending_tool_confirmations;
DROP TABLE IF EXISTS note_yjs_states;
DROP TABLE IF EXISTS note_yjs_updates;
DROP TABLE IF EXISTS routine_logs;
DROP TABLE IF EXISTS routines;
DROP TABLE IF EXISTS agent_working_memory;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS memories;
DROP TABLE IF EXISTS souls;
DROP TABLE IF EXISTS note_tags;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS contexts;
DROP TABLE IF EXISTS telegram_messages;
DROP TABLE IF EXISTS telegram_sessions;
DROP TABLE IF EXISTS telegram_link_codes;
DROP TABLE IF EXISTS telegram_links;
DROP TABLE IF EXISTS note_embeddings;

-- Drop search/embedding columns from notes
ALTER TABLE notes DROP COLUMN IF EXISTS search_vector;
ALTER TABLE notes DROP COLUMN IF EXISTS embedding_status;

-- Drop context_id from notes (FK removed above)
ALTER TABLE notes DROP COLUMN IF EXISTS context_id;
