import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  test('Check DB for hidden notes', () async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'supanotes.sqlite'));
    
    print('DB path: ${file.path}');
    if (!file.existsSync()) {
      print('DB file does not exist!');
      return;
    }
    
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
  });
}
