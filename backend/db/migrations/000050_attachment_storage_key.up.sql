-- Migration 000049 normalised legacy attachment URLs to private object keys.
-- This migration gives that value its semantic name. It is reversible because
-- the previous migration guarantees that all values are storage keys.
ALTER TABLE attachments RENAME COLUMN url TO storage_key;
