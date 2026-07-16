import 'dart:io';
import 'package:drift/native.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:supanotes/features/notes/domain/yjs_node_codec.dart';

void main() async {
  // Use windows specific local app data path (which is what Drift uses on Windows usually? No, getApplicationDocumentsDirectory is used)
  final documentsDir = Directory('C:\\Users\\rigleyc\\Documents');
  final dbFile = File('${documentsDir.path}\\supanotes.sqlite');
  
  if (!dbFile.existsSync()) {
    print('DB not found at ${dbFile.path}');
    return;
  }
  
  print('Found DB at ${dbFile.path}');
  final db = AppDatabase.test(executor: NativeDatabase(dbFile));
  
  // Get the most recently updated note
  final note = await (db.select(db.notes)
    ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
    ..limit(1))
    .getSingleOrNull();
    
  if (note == null) {
    print('No notes found.');
    return;
  }
  
  print('Note: ${note.id} (updated: ${note.updatedAt})');
  
  // Get the Yjs state
  final stateRow = await (db.select(db.localYjsStates)
    ..where((t) => t.noteId.equals(note.id)))
    .getSingleOrNull();
    
  if (stateRow == null) {
    print('No Yjs state found for note.');
    return;
  }
  
  print('State size: ${stateRow.state.length} bytes');
  
  final doc = Doc();
  applyUpdateV2(doc, stateRow.state);
  
  final nodes = noteNodesFromDoc(doc);
  print('Nodes in YDoc (${nodes.length}):');
  for (int i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    print('[$i] ${n.id} @ ${n.position} (type: ${n.type}) -> ${n.data}');
  }
}
