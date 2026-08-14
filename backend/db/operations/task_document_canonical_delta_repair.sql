-- One-time repair for persisted document snapshots.
--
-- This is an operational data conversion, not a runtime compatibility path.
-- It reproduces the existing internal document normalizer for only the
-- deterministic cases that were found in production:
--   * missing or null delta -> []
--   * empty/non-content delta operations -> removed
--
-- Any other invalid delta shape aborts the transaction. Do not extend this
-- script by guessing how to convert embedded or otherwise unknown content.

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET TIME ZONE 'UTC';

DO $$
DECLARE
    unsafe_count integer;
BEGIN
    WITH document_blocks AS (
        SELECT
            n.id AS note_id,
            block
        FROM notes AS n
        CROSS JOIN LATERAL jsonb_array_elements(
            CASE
                WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                    THEN n.document -> 'blocks'
                ELSE '[]'::jsonb
            END
        ) AS blocks(block)
        WHERE n.deleted_at IS NULL
    ), delta_operations AS (
        SELECT
            note_id,
            block ->> 'id' AS block_id,
            operation
        FROM document_blocks
        CROSS JOIN LATERAL jsonb_array_elements(
            CASE
                WHEN jsonb_typeof(block -> 'delta') = 'array'
                    THEN block -> 'delta'
                ELSE '[]'::jsonb
            END
        ) AS operations(operation)
    ), unsafe_shapes AS (
        SELECT note_id
        FROM document_blocks
        WHERE jsonb_typeof(block) IS DISTINCT FROM 'object'
        UNION ALL
        SELECT note_id
        FROM document_blocks
        WHERE jsonb_typeof(block -> 'delta') IS DISTINCT FROM 'array'
          AND jsonb_typeof(block -> 'delta') IS NOT NULL
          AND jsonb_typeof(block -> 'delta') <> 'null'
        UNION ALL
        SELECT note_id
        FROM delta_operations
        WHERE jsonb_typeof(operation) IS DISTINCT FROM 'object'
           OR (
               jsonb_typeof(operation -> 'insert') IS DISTINCT FROM 'string'
               AND NOT (
                   NOT (operation ? 'insert')
                   AND (
                       operation = '{}'::jsonb
                       OR operation ? 'delete'
                       OR operation ? 'retain'
                   )
               )
           )
    )
    SELECT count(*) INTO unsafe_count
    FROM unsafe_shapes;

    IF unsafe_count > 0 THEN
        RAISE EXCEPTION
            'canonical delta repair stopped: % unsafe delta shapes require manual review',
            unsafe_count;
    END IF;
END $$;

CREATE TEMP TABLE canonical_delta_repair_targets ON COMMIT DROP AS
WITH document_blocks AS (
    SELECT
        n.id AS note_id,
        block_index,
        block
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) WITH ORDINALITY AS blocks(block, block_index)
    WHERE n.deleted_at IS NULL
), repaired_blocks AS (
    SELECT
        note_id,
        jsonb_agg(
            CASE
                WHEN jsonb_typeof(block -> 'delta') IS DISTINCT FROM 'array'
                    THEN jsonb_set(block, '{delta}', '[]'::jsonb, true)
                ELSE jsonb_set(
                    block,
                    '{delta}',
                    COALESCE(
                        (
                            SELECT jsonb_agg(
                                operations.operation
                                ORDER BY operations.operation_index
                            )
                            FROM jsonb_array_elements(block -> 'delta')
                                WITH ORDINALITY AS operations(
                                    operation,
                                    operation_index
                                )
                            WHERE jsonb_typeof(operations.operation -> 'insert') = 'string'
                        ),
                        '[]'::jsonb
                    ),
                    true
                )
            END
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
    'canonical_delta_repair_target_notes' AS metric,
    count(*)::text AS value
FROM canonical_delta_repair_targets;

SELECT
    'canonical_delta_repair_target_blocks' AS metric,
    count(*)::text AS value
FROM canonical_delta_repair_targets AS targets
CROSS JOIN LATERAL jsonb_array_elements(targets.old_document -> 'blocks') AS old_blocks(block)
WHERE NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(targets.new_document -> 'blocks') AS new_blocks(block)
    WHERE new_blocks.block ->> 'id' = old_blocks.block ->> 'id'
      AND new_blocks.block = old_blocks.block
);

UPDATE notes AS n
SET
    document = targets.new_document,
    updated_at = now()
FROM canonical_delta_repair_targets AS targets
WHERE n.id = targets.note_id;

SELECT
    'canonical_delta_repair_updated_notes' AS metric,
    count(*)::text AS value
FROM canonical_delta_repair_targets;

COMMIT;
