-- This rollback is intentionally conservative. It only removes the
-- migration shape from untouched revision-zero notes.
UPDATE notes
SET document = '{"schemaVersion":1,"blocks":[]}'::jsonb
WHERE revision = 0
  AND snapshot_revision = 0
  AND jsonb_array_length(document->'blocks') = 1
  AND document #>> '{blocks,0,id}' = 'init'
  AND document #>> '{blocks,0,type}' = 'paragraph';
