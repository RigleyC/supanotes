CREATE TABLE note_share_links (
    note_id    UUID PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
    token_id   UUID NOT NULL UNIQUE,
    enabled    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION disable_note_share_link_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        UPDATE note_share_links SET enabled = FALSE, updated_at = NOW()
        WHERE note_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_disable_note_share_link_on_delete
AFTER UPDATE OF deleted_at ON notes
FOR EACH ROW EXECUTE FUNCTION disable_note_share_link_on_delete();
