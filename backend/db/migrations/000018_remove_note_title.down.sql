ALTER TABLE notes ADD COLUMN title TEXT;

CREATE OR REPLACE FUNCTION generate_note_search_vector() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') ||
                         setweight(to_tsvector('simple', NEW.content), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_generate_note_search_vector ON notes;
CREATE TRIGGER trg_generate_note_search_vector
BEFORE INSERT OR UPDATE OF title, content ON notes
FOR EACH ROW EXECUTE FUNCTION generate_note_search_vector();
