-- One-time repair for malformed Markdown link attributions in persisted
-- document snapshots.
--
-- This is an operational data conversion, not a runtime compatibility path.
-- The editor stored eight malformed link attributions after Markdown text was
-- pasted into one production note. The text inserts are valid; the links are
-- not valid URLs for the strict Go reader. Removing those attributions keeps
-- the text and produces a canonical text-only span.
--
-- Only the two observed malformed shapes are converted. Any other invalid
-- shape aborts the transaction and requires manual review.

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET TIME ZONE 'UTC';

DO $$
DECLARE
    unsafe_count integer;
BEGIN
    WITH candidate_notes AS (
        SELECT n.id AS note_id, n.document
        FROM notes AS n
        WHERE n.deleted_at IS NULL
          AND (
              n.document::text LIKE '%link:https://%60%'
              OR n.document::text LIKE '%link:https://(%60%'
          )
    ), document_blocks AS (
        SELECT
            note_id,
            block
        FROM candidate_notes
        CROSS JOIN LATERAL jsonb_array_elements(
            CASE
                WHEN jsonb_typeof(document -> 'blocks') = 'array'
                    THEN document -> 'blocks'
                ELSE '[]'::jsonb
            END
        ) AS blocks(block)
    ), delta_operations AS (
        SELECT
            note_id,
            block,
            operation
        FROM document_blocks
        CROSS JOIN LATERAL jsonb_array_elements(
            CASE
                WHEN jsonb_typeof(block -> 'delta') = 'array'
                    THEN block -> 'delta'
                ELSE '[]'::jsonb
            END
        ) AS operations(operation)
    ), delta_attributes AS (
        SELECT
            note_id,
            operation,
            attribute_key,
            attribute_value
        FROM delta_operations
        CROSS JOIN LATERAL jsonb_each(
            CASE
                WHEN jsonb_typeof(operation -> 'attributes') = 'object'
                    THEN operation -> 'attributes'
                ELSE '{}'::jsonb
            END
        ) AS attributes(attribute_key, attribute_value)
    ), unsafe_shapes AS (
        SELECT note_id
        FROM document_blocks
        WHERE jsonb_typeof(block) IS DISTINCT FROM 'object'
           OR jsonb_typeof(block -> 'delta') IS DISTINCT FROM 'array'
        UNION ALL
        SELECT note_id
        FROM delta_operations
        WHERE jsonb_typeof(operation) IS DISTINCT FROM 'object'
           OR jsonb_typeof(operation -> 'insert') IS DISTINCT FROM 'string'
           OR (
               operation ? 'attributes'
               AND jsonb_typeof(operation -> 'attributes') IS DISTINCT FROM 'object'
               AND jsonb_typeof(operation -> 'attributes') IS NOT NULL
               AND jsonb_typeof(operation -> 'attributes') <> 'null'
           )
        UNION ALL
        SELECT note_id
        FROM delta_attributes
        WHERE (attribute_key = 'link'
               AND jsonb_typeof(attribute_value) IS DISTINCT FROM 'string')
           OR (attribute_key LIKE 'link:%'
               AND attribute_value IS DISTINCT FROM 'true'::jsonb
               AND attribute_key NOT LIKE 'link:https://%60%'
               AND attribute_key NOT LIKE 'link:https://(%60%')
    )
    SELECT count(*) INTO unsafe_count
    FROM unsafe_shapes;

    IF unsafe_count > 0 THEN
        RAISE EXCEPTION
            'canonical link repair stopped: % unsafe shapes require manual review',
            unsafe_count;
    END IF;
END $$;

CREATE TEMP TABLE canonical_link_repair_targets ON COMMIT DROP AS
WITH candidate_notes AS (
    SELECT n.id AS note_id, n.document
    FROM notes AS n
    WHERE n.deleted_at IS NULL
      AND (
          n.document::text LIKE '%link:https://%60%'
          OR n.document::text LIKE '%link:https://(%60%'
      )
), document_blocks AS (
    SELECT
        note_id,
        block_index,
        block
    FROM candidate_notes
    CROSS JOIN LATERAL jsonb_array_elements(document -> 'blocks')
        WITH ORDINALITY AS blocks(block, block_index)
), repaired_blocks AS (
    SELECT
        note_id,
        jsonb_agg(
            jsonb_set(
                block,
                '{delta}',
                COALESCE(
                    (
                        SELECT jsonb_agg(
                            CASE
                                WHEN jsonb_typeof(operation -> 'attributes') =
                                    'object'
                                    THEN CASE
                                        WHEN EXISTS (
                                            SELECT 1
                                            FROM jsonb_each(
                                                operation -> 'attributes'
                                            ) AS attributes(
                                                attribute_key,
                                                attribute_value
                                            )
                                            WHERE NOT (
                                                attributes.attribute_key LIKE
                                                    'link:https://%60%'
                                                OR attributes.attribute_key LIKE
                                                    'link:https://(%60%'
                                            )
                                        )
                                            THEN jsonb_set(
                                                operation,
                                                '{attributes}',
                                                (
                                                    SELECT jsonb_object_agg(
                                                        attributes.attribute_key,
                                                        attributes.attribute_value
                                                    )
                                                    FROM jsonb_each(
                                                        operation -> 'attributes'
                                                    ) AS attributes(
                                                        attribute_key,
                                                        attribute_value
                                                    )
                                                    WHERE NOT (
                                                        attributes.attribute_key LIKE
                                                            'link:https://%60%'
                                                        OR attributes.attribute_key LIKE
                                                            'link:https://(%60%'
                                                    )
                                                ),
                                                true
                                            )
                                        ELSE operation - 'attributes'
                                    END
                                ELSE operation
                            END
                            ORDER BY operations.operation_index
                        )
                        FROM jsonb_array_elements(block -> 'delta')
                            WITH ORDINALITY AS operations(operation, operation_index)
                    ),
                    '[]'::jsonb
                ),
                true
            )
            ORDER BY block_index
        ) AS blocks
    FROM document_blocks
    GROUP BY note_id
)
SELECT
    n.id AS note_id,
    n.document AS old_document,
    jsonb_set(n.document, '{blocks}', repaired.blocks, true) AS new_document
FROM notes AS n
JOIN repaired_blocks AS repaired ON repaired.note_id = n.id
WHERE n.deleted_at IS NULL
  AND n.document IS DISTINCT FROM
      jsonb_set(n.document, '{blocks}', repaired.blocks, true);

SELECT
    'canonical_link_repair_target_notes' AS metric,
    count(*)::text AS value
FROM canonical_link_repair_targets;

SELECT
    'canonical_link_repair_target_blocks' AS metric,
    count(*)::text AS value
FROM canonical_link_repair_targets AS targets
CROSS JOIN LATERAL jsonb_array_elements(targets.old_document -> 'blocks')
    AS old_blocks(block)
WHERE NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(targets.new_document -> 'blocks')
        AS new_blocks(block)
    WHERE new_blocks.block ->> 'id' = old_blocks.block ->> 'id'
      AND new_blocks.block = old_blocks.block
);

UPDATE notes AS n
SET
    document = targets.new_document,
    updated_at = now()
FROM canonical_link_repair_targets AS targets
WHERE n.id = targets.note_id;

SELECT
    'canonical_link_repair_updated_notes' AS metric,
    count(*)::text AS value
FROM canonical_link_repair_targets;

COMMIT;
