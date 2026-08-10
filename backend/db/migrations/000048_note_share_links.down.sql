DROP TRIGGER IF EXISTS trg_disable_note_share_link_on_delete ON notes;
DROP FUNCTION IF EXISTS disable_note_share_link_on_delete();
DROP TABLE IF EXISTS note_share_links;
