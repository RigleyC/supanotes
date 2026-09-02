BEGIN;

DROP TRIGGER IF EXISTS trg_user_note_preferences_sync_change ON user_note_preferences;
DROP FUNCTION IF EXISTS emit_note_preference_sync_change();
DROP TRIGGER IF EXISTS trg_note_shares_sync_change ON note_shares;
DROP FUNCTION IF EXISTS emit_note_share_sync_change();
DROP TRIGGER IF EXISTS trg_notes_sync_change ON notes;
DROP FUNCTION IF EXISTS emit_note_sync_change();
DROP TABLE IF EXISTS sync_changes;

COMMIT;
