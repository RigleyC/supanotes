-- Values remain private storage keys when the column name is restored.
ALTER TABLE attachments RENAME COLUMN storage_key TO url;
