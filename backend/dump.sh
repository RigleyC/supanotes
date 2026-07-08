#!/bin/bash
export PGPASSWORD="4yfVB4Dn5oZV9Ai"
pg_dumpall -h 127.0.0.1 -p 5432 -U postgres > /tmp/backup.sql || pg_dumpall -h 127.0.0.1 -p 5433 -U postgres > /tmp/backup.sql
