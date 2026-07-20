ALTER TABLE tasks
    DROP COLUMN reminder;

ALTER TABLE tasks
    DROP COLUMN has_time;

ALTER TABLE tasks
    ALTER COLUMN due_date TYPE date USING (due_date::date);
