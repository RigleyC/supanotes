-- Step 1: Drop the FTS trigger so we can replace the function
DROP TRIGGER IF EXISTS trg_generate_note_search_vector ON notes;

-- Step 2: Rewrite the FTS function to remove title references
CREATE OR REPLACE FUNCTION generate_note_search_vector() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := setweight(to_tsvector('simple', NEW.content), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 3: Recreate trigger on content only
CREATE TRIGGER trg_generate_note_search_vector
BEFORE INSERT OR UPDATE OF content ON notes
FOR EACH ROW EXECUTE FUNCTION generate_note_search_vector();

-- Step 4: Drop the title column (breaking change)
ALTER TABLE notes DROP COLUMN IF EXISTS title;
