-- Force all mutations to note_nodes through the Yjs mutation flow
-- by revoking direct INSERT / UPDATE / DELETE from the application role.
--
-- The application connects with the role defined in DATABASE_URL.
-- Since we don't know the exact role name at migration time, we revoke
-- from PUBLIC so that every non-owner role loses write access.
--
-- SELECT is kept so reads (GetNodesByNoteId, GetNoteByID, etc.) still work.
-- The Yjs projection (ProjectToDB) runs inside a transaction that uses
-- pg_advisory_xact_lock and the connection pool still owns the table, so
-- the projection upsert succeeds.

REVOKE INSERT, UPDATE, DELETE ON note_nodes FROM PUBLIC;
