-- Migration 000039 removed notes.search_vector but left behind the trigger
-- function that still assigns NEW.search_vector. Any later INSERT/UPDATE of
-- notes.content then fails with SQLSTATE 42703. Remove both stale objects.
DROP TRIGGER IF EXISTS trg_generate_note_search_vector ON notes;
DROP FUNCTION IF EXISTS generate_note_search_vector();
