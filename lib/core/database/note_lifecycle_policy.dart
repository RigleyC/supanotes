/// SQL predicate shared by catalog visibility and local draft cleanup.
///
/// The `n` alias must refer to the `notes` table. Keep all content that makes
/// a local note meaningful in this one predicate.
const untouchedLocalDraftPredicate = """
n.has_remote_copy = 0
AND TRIM(n.content) = ''
AND NOT EXISTS (
  SELECT 1 FROM tasks t
  WHERE t.note_id = n.id AND t.deleted_at IS NULL
)
AND NOT EXISTS (
  SELECT 1 FROM attachments a
  WHERE a.note_id = n.id
)
AND NOT EXISTS (
  SELECT 1 FROM pending_note_operations p
  WHERE p.note_id = n.id
)
AND NOT EXISTS (
  SELECT 1 FROM sync_sessions s
  WHERE s.note_id = n.id
)
""";
