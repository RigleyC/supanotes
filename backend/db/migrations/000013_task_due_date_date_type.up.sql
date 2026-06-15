BEGIN;

ALTER TABLE tasks
    ALTER COLUMN due_date TYPE date USING (due_date::date);

COMMIT;
