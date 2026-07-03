import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final dbPath = '${Platform.environment['USERPROFILE']}\\Documents\\supanotes.sqlite';
  print('Checking DB at $dbPath');
  
  if (!File(dbPath).existsSync()) {
    print('DB not found!');
    return;
  }
  
  final db = sqlite3.open(dbPath);
  
  // Count total notes
  final totalNotes = db.select('SELECT COUNT(*) as c FROM notes').first['c'];
  print('Total notes: $totalNotes');
  
  // Notes missing from the list (content is empty)
  final missingNotes = db.select("SELECT id, content FROM notes WHERE trim(content) = ''");
  print('Notes with empty content: ${missingNotes.length}');
  
  for (final row in missingNotes) {
    print('  - Note ID: ${row['id']}, Content length: ${row['content'].toString().length}');
    
    // Check if they have node_nodes
    final nodes = db.select("SELECT count(*) as c FROM note_nodes WHERE note_id = ?", [row['id']]).first['c'];
    print('    - Has $nodes note_nodes');
  }
  
  db.dispose();
}
