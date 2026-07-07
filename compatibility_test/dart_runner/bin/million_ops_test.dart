import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/utils/snapshot.dart';
import 'package:yjs_dart/src/structs/item.dart';
import 'package:yjs_dart/src/structs/content.dart';
import 'package:yjs_dart/src/utils/struct_store.dart';
import 'package:yjs_dart/src/utils/id_set.dart' hide findIndexSS;
import 'package:yjs_dart/src/lib0/encoding.dart';

void main() {
  // Override buggy _ContentStringStub with real ContentString reader
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);

  print('=======================================');
  print('Running 1 Million Operations Spike');
  print('=======================================');

  var doc = Doc(DocOpts(gc: false, clientID: 65));
  var text = doc.getText('note')!;
  final random = Random(42);

  final stopwatch = Stopwatch()..start();
  var localLen = 0;

  // 1. Generate 1,000 typing sessions of 1,000 edits = 1,000,000 operations
  const numSessions = 1000;
  const charsPerSession = 1000;

  for (var session = 1; session <= numSessions; session++) {
    // Pick a random cursor position
    var cursor = localLen > 0 ? random.nextInt(localLen + 1) : 0;
    
    doc.transact((tr) {
      for (var c = 0; c < charsPerSession; c++) {
        text.insert(cursor, 'a');
        cursor++;
        localLen++;
      }
    });

    // Periodically log progress (every 100k ops)
    if ((session * charsPerSession) % 100000 == 0) {
      final elapsed = stopwatch.elapsedMilliseconds / 1000;
      print('Generated ${(session * charsPerSession)} / 1,000,000 ops | Elapsed: ${elapsed.toStringAsFixed(1)}s | Current Text Length: $localLen');
      
      // Periodically compact history using snapshot/pruning to keep memory low
      final snap = snapshot(doc);
      // Use a fresh clientID to avoid the Doc.clientID setter runtime bug
      final newDoc = Doc(DocOpts(gc: false, clientID: 66 + session));
      newDoc.getText('note');
      customCreateDocFromSnapshot(doc, snap, newDoc);
      
      // Pivot to the compacted doc
      doc = newDoc;
      text = doc.getText('note')!;
    }
  }

  // 2. Save final state to binary update payload
  print('Saving final state to binary update payload...');
  final savedUpdateBytes = encodeStateAsUpdate(doc);

  // 3. Load the saved state into a fresh document client
  print('Loading saved state into a fresh document client...');
  final freshDoc = Doc(DocOpts(gc: false, clientID: 9999));
  final freshText = freshDoc.getText('note')!;
  applyUpdate(freshDoc, savedUpdateBytes);

  print('Verifying loaded state consistency...');
  final finalStr = freshText.toString();
  if (finalStr.length != localLen) {
    print('❌ Loaded document length mismatch! Expected $localLen, got ${finalStr.length}');
    exit(1);
  }

  // 4. Continue editing the loaded document (add 1,000 edits)
  print('Continuing editing on loaded document (adding 1,000 edits)...');
  freshDoc.transact((tr) {
    for (var i = 0; i < 1000; i++) {
      freshText.insert(0, 'x');
    }
  });

  final finalLengthAfterEdits = freshText.toString().length;
  print('Final length after additional edits: $finalLengthAfterEdits');

  stopwatch.stop();
  print('=======================================');
  print('✅ 1 Million Operations Spike Passed Successfully!');
  print('Total Time: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
  print('=======================================');
}

// Custom V1 Snapshot Restore helper
void customCreateDocFromSnapshot(Doc sourceDoc, Snapshot snap, Doc targetDoc) {
  final encoder = UpdateEncoderV1();
  final store = sourceDoc.store;
  
  transact(sourceDoc, (transaction) {
    final clients = <int, int>{};
    snap.sv.forEach((client, clock) {
      if (clock > 0) {
        clients[client] = clock;
      }
    });

    final sortedClients = clients.keys.toList()..sort((a, b) => b - a);
    writeVarUint(encoder.restEncoder, sortedClients.length);
    for (final client in sortedClients) {
      final clock = clients[client]!;
      final structs = store.clients[client] ?? [];
      final lastStructIndex = findIndexSS(structs, clock - 1);
      writeVarUint(encoder.restEncoder, lastStructIndex + 1);
      encoder.writeClient(client);
      writeVarUint(encoder.restEncoder, 0);
      for (var i = 0; i <= lastStructIndex; i++) {
        (structs[i] as dynamic).write(encoder, 0, 0);
      }
    }
    writeIdSet(encoder, snap.ds);
  });

  applyUpdate(targetDoc, encoder.toUint8Array());
}
