-- Notify connected WS handlers when a user's edit permission is revoked.
-- The WS handler listens on the 'permission_revoked' channel and sets
-- canEdit=false for matching connections.

CREATE OR REPLACE FUNCTION notify_permission_revoked()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' OR (OLD.permission = 'edit' AND NEW.permission != 'edit') THEN
        PERFORM pg_notify('permission_revoked', json_build_object(
            'note_id', COALESCE(OLD.note_id, NEW.note_id)::TEXT,
            'user_id', COALESCE(OLD.user_id, NEW.user_id)::TEXT
        )::TEXT);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER permission_revoked_trigger
    AFTER DELETE OR UPDATE ON note_shares
    FOR EACH ROW EXECUTE FUNCTION notify_permission_revoked();
