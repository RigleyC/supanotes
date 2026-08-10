-- This migration is intentionally irreversible. It replaced copied public URLs
-- with private storage keys, so the old values cannot be reconstructed safely.
DO $$
BEGIN
    RAISE EXCEPTION 'migration 000049_private_attachment_keys is irreversible';
END
$$;
