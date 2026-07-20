ALTER TABLE tasks
    ALTER COLUMN due_date TYPE timestamptz USING (due_date::timestamptz);

ALTER TABLE tasks
    ADD COLUMN has_time BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE tasks
    ADD COLUMN reminder TEXT;
