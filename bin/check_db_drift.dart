import 'package:supanotes/core/database/database.dart';

void main() async {
  print('Initializing AppDatabase...');
  final db = AppDatabase();
  
  try {
    final allNotes = await db.select(db.notes).get();
    print('Total notes in DB: ${allNotes.length}');
    
    int missingCount = 0;
    for (final note in allNotes) {
      if (note.content.trim().isEmpty) {
        missingCount++;
        final nodes = await (db.select(db.noteNodes)..where((t) => t.noteId.equals(note.id))).get();
        print('  - Note ID: ${note.id}, content length: 0, has ${nodes.length} note_nodes');
      }
    }
    
    print('Total notes with empty content (hidden from UI): $missingCount');
  } catch (e) {
    print('Error querying DB: $e');
  } finally {
    await db.close();
  }
}
