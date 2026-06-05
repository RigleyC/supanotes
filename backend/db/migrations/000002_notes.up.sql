-- Feature 2 — Notes CRUD, Inbox, Contexts, Tags

CREATE TABLE contexts (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    slug       TEXT NOT NULL,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, slug)
);

CREATE TABLE notes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    context_id UUID REFERENCES contexts(id) ON DELETE SET NULL,
    title      TEXT,
    content    TEXT NOT NULL,
    excerpt    TEXT,
    is_inbox   BOOLEAN NOT NULL DEFAULT false,
    favorite   BOOLEAN NOT NULL DEFAULT false,
    archived   BOOLEAN NOT NULL DEFAULT false,
    search_vector tsvector,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX idx_notes_single_inbox ON notes (user_id) WHERE is_inbox = true AND deleted_at IS NULL;
CREATE INDEX idx_notes_user_updated ON notes (user_id, updated_at DESC);
CREATE INDEX idx_notes_search ON notes USING GIN (search_vector);

CREATE TABLE tags (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, name)
);

CREATE TABLE note_tags (
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (note_id, tag_id)
);

CREATE TABLE note_links (
    source_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    PRIMARY KEY (source_id, target_id)
);

CREATE TABLE attachments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id    UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    filename   TEXT NOT NULL,
    url        TEXT NOT NULL,
    mime_type  TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Function for extracting excerpt from markdown content (first N chars, simplified)
CREATE OR REPLACE FUNCTION generate_note_excerpt() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.excerpt IS NULL OR NEW.excerpt = '' THEN
        -- basic truncation to 140 characters
        NEW.excerpt := substring(NEW.content from 1 for 140);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_note_excerpt
BEFORE INSERT OR UPDATE OF content ON notes
FOR EACH ROW EXECUTE FUNCTION generate_note_excerpt();

-- Trigger for FTS (Full Text Search) using simple configuration
CREATE OR REPLACE FUNCTION generate_note_search_vector() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') || 
                         setweight(to_tsvector('simple', NEW.content), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_note_search_vector
BEFORE INSERT OR UPDATE OF title, content ON notes
FOR EACH ROW EXECUTE FUNCTION generate_note_search_vector();
