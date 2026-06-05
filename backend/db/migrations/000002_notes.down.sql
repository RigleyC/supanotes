DROP TRIGGER IF EXISTS trg_generate_note_search_vector ON notes;
DROP FUNCTION IF EXISTS generate_note_search_vector();

DROP TRIGGER IF EXISTS trg_generate_note_excerpt ON notes;
DROP FUNCTION IF EXISTS generate_note_excerpt();

DROP TABLE IF EXISTS attachments;
DROP TABLE IF EXISTS note_links;
DROP TABLE IF EXISTS note_tags;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS notes;
DROP TABLE IF EXISTS contexts;
