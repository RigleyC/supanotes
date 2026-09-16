CREATE TABLE attachment_deletion_outbox (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    storage_key  TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'processing')),
    attempts     INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_error   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX attachment_deletion_outbox_active_key_idx
    ON attachment_deletion_outbox (storage_key)
    WHERE status IN ('pending', 'processing');

CREATE INDEX attachment_deletion_outbox_ready_idx
    ON attachment_deletion_outbox (available_at, created_at)
    WHERE status = 'pending';

CREATE OR REPLACE FUNCTION enqueue_attachment_deletion()
RETURNS TRIGGER AS $$
BEGIN
    -- Uploads acquire the same transaction-scoped lock before inserting a
    -- reference. This closes the race between the last reference disappearing
    -- and the cleanup worker deleting the object.
    PERFORM pg_advisory_xact_lock(hashtextextended(OLD.storage_key, 0));

    IF NOT EXISTS (
        SELECT 1 FROM attachments WHERE storage_key = OLD.storage_key
    ) THEN
        INSERT INTO attachment_deletion_outbox (storage_key)
        VALUES (OLD.storage_key)
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER attachments_enqueue_deletion
AFTER DELETE ON attachments
FOR EACH ROW EXECUTE FUNCTION enqueue_attachment_deletion();

-- Claim one item while holding the storage-key advisory lock. The PL/pgSQL
-- function deliberately acquires the lock before checking references so each
-- statement gets a fresh READ COMMITTED snapshot after a concurrent insert
-- finishes. Processing rows are leased and become retryable after a crash.
CREATE OR REPLACE FUNCTION claim_attachment_storage_deletion(requested_key TEXT DEFAULT NULL)
RETURNS TABLE (id UUID, storage_key TEXT, referenced BOOLEAN) AS $$
DECLARE
    candidate RECORD;
BEGIN
    SELECT d.id, d.storage_key
    INTO candidate
    FROM attachment_deletion_outbox d
    WHERE (requested_key IS NULL OR d.storage_key = requested_key)
      AND (
          (d.status = 'pending' AND d.available_at <= NOW())
          OR (d.status = 'processing' AND d.updated_at < NOW() - INTERVAL '5 minutes')
      )
    ORDER BY d.created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(candidate.storage_key, 0));

    UPDATE attachment_deletion_outbox
    SET status = 'processing',
        attempts = attempts + 1,
        updated_at = NOW()
    WHERE attachment_deletion_outbox.id = candidate.id;

    id := candidate.id;
    storage_key := candidate.storage_key;
    SELECT EXISTS (
        SELECT 1 FROM attachments a WHERE a.storage_key = candidate.storage_key
    ) INTO referenced;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;
