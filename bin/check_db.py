import sqlite3
import os

db_path = os.path.expandvars(r'%USERPROFILE%\Documents\supanotes.sqlite')
print(f"Checking DB at {db_path}")

if not os.path.exists(db_path):
    print("DB file not found!")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT COUNT(*) FROM notes")
print(f"Total notes: {cursor.fetchone()[0]}")

cursor.execute("SELECT id, content, deleted_at FROM notes WHERE trim(content) = '' AND deleted_at IS NULL")
empty_notes = cursor.fetchall()
print(f"Notes with empty content (not deleted): {len(empty_notes)}")

for note_id, content, deleted_at in empty_notes:
    cursor.execute("SELECT COUNT(*) FROM note_nodes WHERE note_id = ?", (note_id,))
    node_count = cursor.fetchone()[0]
    print(f"  - Note ID: {note_id}, nodes: {node_count}")

conn.close()
