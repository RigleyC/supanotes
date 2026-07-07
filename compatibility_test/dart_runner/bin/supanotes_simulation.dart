import 'dart:convert';
import 'dart:io';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/structs/item.dart';
import 'package:yjs_dart/src/structs/content.dart';

void main() {
  // Override buggy _ContentStringStub with real ContentString reader
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);

  print('=======================================');
  print('Running SupaNotes Document Simulation');
  print('=======================================');

  // Initialize 3 clients
  final clientA = Doc(DocOpts(gc: false, clientID: 65));
  final clientB = Doc(DocOpts(gc: false, clientID: 66));
  final clientC = Doc(DocOpts(gc: false, clientID: 67));

  final clients = {'A': clientA, 'B': clientB, 'C': clientC};

  // Helper to initialize types on a Doc
  void initDocSchema(Doc doc) {
    doc.getText('title');
    doc.getArray('checklist');
    doc.getText('markdown');
    doc.getArray('table');
    doc.getText('code');
    doc.getArray('tasks');
    doc.getMap('metadata');
  }

  clients.values.forEach(initDocSchema);

  // 1. Initial State Setup on Client A
  clientA.transact((tr) {
    clientA.getText('title')!.insert(0, 'SupaNotes Release Plan');
    clientA.getText('markdown')!.insert(0, '# Release Plan\nWe are going to deploy CRDT sync.');
    clientA.getText('code')!.insert(0, 'void main() {\n  print("Hello Yjs");\n}');
    
    // Checklist: YArray of YMaps
    final checklist = clientA.getArray('checklist')!;
    final item1 = YMap();
    final item2 = YMap();
    checklist.insert(0, [item1, item2]);
    
    item1.set('text', 'Setup Go relay server');
    item1.set('done', true);
    
    item2.set('text', 'Run 10k fuzzing cycles');
    item2.set('done', false);

    // Table: YArray of YArrays
    final table = clientA.getArray('table')!;
    final row1 = YArray();
    final row2 = YArray();
    table.insert(0, [row1, row2]);
    row1.insert(0, ['Task Name', 'Assignee', 'Status']);
    row2.insert(0, ['Fuzzing', 'Antigravity', 'Done']);

    // Tasks: YArray of Strings
    final tasks = clientA.getArray('tasks')!;
    tasks.insert(0, ['task_101', 'task_102']);

    // Metadata: YMap
    final metadata = clientA.getMap('metadata')!;
    metadata.set('created_at', 1783448400000);
    metadata.set('last_modified_by', 'UserA');
    final tags = YArray();
    metadata.set('tags', tags);
    tags.insert(0, ['sync', 'crdt', 'spike']);
  });

  print('Initial note populated on Client A.');

  // Sync Client A to B and C
  final uInit = encodeStateAsUpdate(clientA);
  applyUpdate(clientB, uInit);
  applyUpdate(clientC, uInit);

  print('Synced initial note to Client B and Client C.');

  // 2. Concurrent Edits from all 3 clients
  print('Performing concurrent edits across Client A, B, and C...');

  // Client A edits title and checklist item 2
  clientA.transact((tr) {
    clientA.getText('title')!.insert(22, ' v2.0');
    final checklist = clientA.getArray('checklist')!;
    // checklist[1] is a YMap
    final item2 = checklist.get(1) as YMap;
    item2.set('done', true);
  });

  // Client B edits markdown content and table row 2 status
  clientB.transact((tr) {
    clientB.getText('markdown')!.insert(51, ' We also support offline editing.');
    final table = clientB.getArray('table')!;
    final row2 = table.get(1) as YArray;
    row2.delete(2, 1);
    row2.insert(2, ['In Progress']);
  });

  // Client C adds a tag to metadata, adds a task, and edits code block
  clientC.transact((tr) {
    final metadata = clientC.getMap('metadata')!;
    final tags = metadata.get('tags') as YArray;
    tags.insert(3, ['production']);
    
    final tasks = clientC.getArray('tasks')!;
    tasks.insert(2, ['task_103']);

    clientC.getText('code')!.insert(29, '\n  print("Ready!");');
  });

  // 3. Broadcast updates
  print('Broadcasting and merging updates...');
  final uA = encodeStateAsUpdate(clientA);
  final uB = encodeStateAsUpdate(clientB);
  final uC = encodeStateAsUpdate(clientC);

  // Deliver A and B and C updates
  applyUpdate(clientB, uA);
  applyUpdate(clientB, uC);

  applyUpdate(clientC, uA);
  applyUpdate(clientC, uB);

  applyUpdate(clientA, uB);
  applyUpdate(clientA, uC);

  // Final sync vector to ensure absolute convergence
  for (var i = 0; i < 5; i++) {
    for (final sender in clients.keys) {
      for (final receiver in clients.keys) {
        if (sender != receiver) {
          final sv = encodeStateVector(clients[receiver]!);
          final diff = encodeStateAsUpdate(clients[sender]!, sv);
          if (diff.length > 2) {
            applyUpdate(clients[receiver]!, diff);
          }
        }
      }
    }
  }

  // 4. Verify Convergence
  final stateA = clients['A']!.getMap('metadata')!.toJson();
  final stateB = clients['B']!.getMap('metadata')!.toJson();
  final stateC = clients['C']!.getMap('metadata')!.toJson();

  final textA = clients['A']!.getText('markdown')!.toString();
  final textB = clients['B']!.getText('markdown')!.toString();
  final textC = clients['C']!.getText('markdown')!.toString();

  final checklistA = jsonEncode(clients['A']!.getArray('checklist')!.toJson());
  final checklistB = jsonEncode(clients['B']!.getArray('checklist')!.toJson());
  final checklistC = jsonEncode(clients['C']!.getArray('checklist')!.toJson());

  var success = true;
  if (textA != textB || textA != textC) {
    print('❌ Markdown Content diverged!');
    success = false;
  }
  if (checklistA != checklistB || checklistA != checklistC) {
    print('❌ Checklist diverged!');
    success = false;
  }

  if (success) {
    print('---------------------------------------');
    print('Title:     "${clients['A']!.getText('title')}"');
    print('Checklist: $checklistA');
    print('Tasks:     ${clients['A']!.getArray('tasks')!.toJson()}');
    print('Metadata:  ${jsonEncode(stateA)}');
    print('=======================================');
    print('✅ SupaNotes Note Simulation Passed Successfully!');
    print('=======================================');
  } else {
    exit(1);
  }
}
