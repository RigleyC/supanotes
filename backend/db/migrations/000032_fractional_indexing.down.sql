-- Down-migration is fundamentally unsafe if lexical string positions (like "a0V") exist.
-- It will crash the cast. This is provided for pre-production rollbacks only.
ALTER TABLE note_nodes ALTER COLUMN position TYPE double precision USING position::double precision;
ALTER TABLE tasks ALTER COLUMN position TYPE double precision USING position::double precision;
