UPDATE attachments
SET url = regexp_replace(url, '^.*/attachments/', 'attachments/')
WHERE url LIKE '%/attachments/%';
