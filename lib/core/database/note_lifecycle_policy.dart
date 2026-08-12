/// Persisted lifecycle values for local notes.
const emptyDraftLifecycleState = 'empty_draft';
const materializedLifecycleState = 'materialized';

/// SQL guard used by the atomic local-draft cleanup.
///
/// The lifecycle state is the canonical definition of whether a local note
/// was touched. The remaining clauses only protect data that is still being
/// persisted or reconciled during teardown.
const untouchedLocalDraftPredicate =
    """
n.lifecycle_state = '$emptyDraftLifecycleState'
AND NOT EXISTS (
  SELECT 1 FROM pending_note_operations p
  WHERE p.note_id = n.id
)
AND NOT EXISTS (
  SELECT 1 FROM sync_sessions s
  WHERE s.note_id = n.id
)
AND NOT EXISTS (
  SELECT 1 FROM note_sync_errors e
  WHERE e.note_id = n.id
)
""";
