DROP TRIGGER IF EXISTS attachments_enqueue_deletion ON attachments;
DROP FUNCTION IF EXISTS claim_attachment_storage_deletion(TEXT);
DROP FUNCTION IF EXISTS enqueue_attachment_deletion();
DROP TABLE IF EXISTS attachment_deletion_outbox;
