-- Notes created before REST/OT became the canonical write path can have a
-- non-empty legacy content column and an empty document snapshot. Preserve
-- that content as the initial canonical paragraph before clients hydrate.
UPDATE notes
SET document = jsonb_build_object(
        'schemaVersion', 1,
        'blocks', jsonb_build_array(
            jsonb_build_object(
                'id', 'init',
                'type', 'paragraph',
                'delta', jsonb_build_array(jsonb_build_object('insert', content)),
                'metadata', '{}'::jsonb
            )
        )
    ),
    updated_at = NOW()
WHERE COALESCE(content, '') <> ''
  AND COALESCE(
        jsonb_array_length(
            CASE
                WHEN jsonb_typeof(document->'blocks') = 'array' THEN document->'blocks'
                ELSE '[]'::jsonb
            END
        ),
        0
    ) = 0;
