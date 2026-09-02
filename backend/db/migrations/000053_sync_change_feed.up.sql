BEGIN;

CREATE TABLE sync_changes (
    sequence BIGSERIAL PRIMARY KEY,
    target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN (
        'note_changed',
        'note_deleted',
        'note_access_changed',
        'note_access_revoked',
        'note_preferences_changed'
    )),
    note_id UUID,
    revision BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sync_changes_target_sequence
    ON sync_changes(target_user_id, sequence);

CREATE OR REPLACE FUNCTION emit_note_sync_change() RETURNS TRIGGER AS $$
DECLARE
    event_kind TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        event_kind := 'note_changed';
    ELSIF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        event_kind := 'note_deleted';
    ELSE
        event_kind := 'note_changed';
    END IF;

    INSERT INTO sync_changes(target_user_id, kind, note_id, revision)
    VALUES (NEW.user_id, event_kind, NEW.id, NEW.revision);

    INSERT INTO sync_changes(target_user_id, kind, note_id, revision)
    SELECT ns.user_id, event_kind, NEW.id, NEW.revision
    FROM note_shares ns
    WHERE ns.note_id = NEW.id
      AND ns.user_id <> NEW.user_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notes_sync_change
AFTER INSERT OR UPDATE ON notes
FOR EACH ROW EXECUTE FUNCTION emit_note_sync_change();

CREATE OR REPLACE FUNCTION emit_note_share_sync_change() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO sync_changes(target_user_id, kind, note_id)
        VALUES (OLD.user_id, 'note_access_revoked', OLD.note_id);
        RETURN OLD;
    END IF;

    INSERT INTO sync_changes(target_user_id, kind, note_id)
    VALUES (NEW.user_id, 'note_access_changed', NEW.note_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_note_shares_sync_change
AFTER INSERT OR UPDATE OR DELETE ON note_shares
FOR EACH ROW EXECUTE FUNCTION emit_note_share_sync_change();

CREATE OR REPLACE FUNCTION emit_note_preference_sync_change() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO sync_changes(target_user_id, kind, note_id)
    VALUES (NEW.user_id, 'note_preferences_changed', NEW.note_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_note_preferences_sync_change
AFTER INSERT OR UPDATE ON user_note_preferences
FOR EACH ROW EXECUTE FUNCTION emit_note_preference_sync_change();

COMMIT;
