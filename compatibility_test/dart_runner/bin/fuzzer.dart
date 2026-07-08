import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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

  // Setup seed
  final seedEnv = Platform.environment['FUZZ_SEED'];
  final seed = seedEnv != null ? int.tryParse(seedEnv) ?? DateTime.now().millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch;
  final random = Random(seed);
  print('=======================================');
  print('Starting Yjs Dart Fuzzing Stress-Test');
  print('Seed: $seed');
  print('=======================================');

  const iterations = 10000;
  for (var iter = 1; iter <= iterations; iter++) {
    if (iter % 1000 == 0) {
      print('Ran $iter / $iterations iterations successfully...');
    }

    try {
      runFuzzIteration(iter, random);
      runPhantomDeleteTest(iter, random);
    } catch (e, stack) {
      print('❌ Fuzzing failed at iteration $iter!');
      print('Seed: $seed');
      print('Error: $e');
      print(stack);
      exit(1);
    }
  }

  print('=======================================');
  print('✅ Fuzzing stress-test completed successfully!');
  print('Ran $iterations / $iterations iterations without divergence.');
  print('=======================================');
}

class FuzzOp {
  final String client;
  final String type; // 'insert', 'delete', 'map', 'array', 'sync', 'sv_sync', 'snapshot'
  final Map<String, dynamic> details;

  FuzzOp(this.client, this.type, this.details);

  @override
  String toString() {
    return 'Client $client: $type $details';
  }
}

Object? _canonicalize(Object? val) {
  if (val is Map) {
    final sortedKeys = val.keys.toList()..sort();
    final res = <String, Object?>{};
    for (final k in sortedKeys) {
      res[k.toString()] = _canonicalize(val[k]);
    }
    return res;
  } else if (val is List) {
    return val.map(_canonicalize).toList();
  }
  return val;
}

void runFuzzIteration(int iterId, Random random) {
  // 1. Choose number of clients (2 to 8)
  final numClients = random.nextInt(7) + 2;
  final clientNames = List.generate(numClients, (i) => String.fromCharCode(65 + i)); // A, B, C, D...

  // 2. Initialize documents
  final docs = <String, Doc>{};
  for (final name in clientNames) {
    final clientID = name.codeUnitAt(0);
    docs[name] = Doc(DocOpts(gc: false, clientID: clientID));
    // Pre-initialize our three tracked types
    docs[name]!.getText('note');
    docs[name]!.getMap('meta');
    docs[name]!.getArray('list');
  }

  final opLog = <FuzzOp>[];
  final networkBuffers = <String, List<Uint8List>>{};
  for (final name in clientNames) {
    networkBuffers[name] = [];
  }

  final snapshotBuffer = <String, Snapshot>{};

  // Perform a random number of concurrent operations (20 to 100)
  final numOps = random.nextInt(81) + 20;

  for (var opIdx = 0; opIdx < numOps; opIdx++) {
    // Pick random client
    final client = clientNames[random.nextInt(clientNames.length)];
    final doc = docs[client]!;

    // Pick random action type
    final actionType = random.nextInt(10);
    switch (actionType) {
      case 0: // text_insert
        final text = doc.getText('note')!;
        final val = 'word_${random.nextInt(100)} ';
        final len = text.toString().length;
        final idx = len > 0 ? random.nextInt(len + 1) : 0;
        doc.transact((tr) {
          text.insert(idx, val);
        });
        opLog.add(FuzzOp(client, 'text_insert', {'val': val, 'index': idx}));
        break;

      case 1: // text_delete
        final text = doc.getText('note')!;
        final len = text.toString().length;
        if (len > 0) {
          final idx = random.nextInt(len);
          final deleteLen = min(random.nextInt(5) + 1, len - idx);
          doc.transact((tr) {
            text.delete(idx, deleteLen);
          });
          opLog.add(FuzzOp(client, 'text_delete', {'index': idx, 'length': deleteLen}));
        }
        break;

      case 2: // map_set
        final map = doc.getMap('meta')!;
        final key = 'key_${random.nextInt(10)}';
        final val = random.nextInt(100);
        doc.transact((tr) {
          map.set(key, val);
        });
        opLog.add(FuzzOp(client, 'map_set', {'key': key, 'value': val}));
        break;

      case 3: // array_insert
        final arr = doc.getArray('list')!;
        var length = 0;
        try {
          length = (arr as dynamic).length as int;
        } catch (_) {}
        final idx = length > 0 ? random.nextInt(length + 1) : 0;
        final val = 'item_${random.nextInt(100)}';
        doc.transact((tr) {
          arr.insert(idx, [val]);
        });
        opLog.add(FuzzOp(client, 'array_insert', {'index': idx, 'value': val}));
        break;

      case 4: // take_snapshot
        final snap = snapshot(doc);
        final snapId = 'snap_${client}_${opIdx}';
        snapshotBuffer[snapId] = snap;
        opLog.add(FuzzOp(client, 'take_snapshot', {'id': snapId}));
        break;

      case 5: // restore_snapshot
        if (snapshotBuffer.isNotEmpty) {
          final snapId = snapshotBuffer.keys.elementAt(random.nextInt(snapshotBuffer.length));
          final snap = snapshotBuffer[snapId]!;
          final sourceClient = snapId.split('_')[1];
          final sourceDoc = docs[sourceClient]!;
          customCreateDocFromSnapshot(sourceDoc, snap, doc);
          opLog.add(FuzzOp(client, 'restore_snapshot', {'snapshot_id': snapId, 'source_client': sourceClient}));
        }
        break;

      case 6: // broadcast update
        final update = encodeStateAsUpdate(doc);
        opLog.add(FuzzOp(client, 'broadcast_update', {}));
        // Put in all other clients' network buffers
        for (final other in clientNames) {
          if (other != client) {
            networkBuffers[other]!.add(update);
          }
        }
        break;

      case 7: // deliver random buffered update (simulating latency / shuffle / duplication)
        final buf = networkBuffers[client]!;
        if (buf.isNotEmpty) {
          final idx = random.nextInt(buf.length);
          final update = buf[idx];
          final duplicate = random.nextDouble() < 0.3;
          if (!duplicate) {
            buf.removeAt(idx);
          }
          applyUpdate(doc, update);
          opLog.add(FuzzOp(client, 'deliver_update', {'duplicate': duplicate}));
        }
        break;

      case 8: // state vector diff sync
        final peer = clientNames[random.nextInt(clientNames.length)];
        if (peer != client) {
          final peerDoc = docs[peer]!;
          final sv = encodeStateVector(peerDoc);
          final diff = encodeStateAsUpdate(doc, sv);
          applyUpdate(peerDoc, diff);
          opLog.add(FuzzOp(client, 'sv_sync_to_peer', {'peer': peer}));
        }
        break;

      case 9: // no-op
        break;
    }
  }

  // Final Sync
  var fullySynced = false;
  var finalSyncLoops = 0;

  while (!fullySynced && finalSyncLoops < 100) {
    fullySynced = true;
    finalSyncLoops++;

    for (final client in clientNames) {
      final buf = networkBuffers[client]!;
      final doc = docs[client]!;
      while (buf.isNotEmpty) {
        final update = buf.removeLast();
        applyUpdate(doc, update);
        fullySynced = false;
      }
    }

    for (var i = 0; i < clientNames.length; i++) {
      for (var j = i + 1; j < clientNames.length; j++) {
        final docA = docs[clientNames[i]]!;
        final docB = docs[clientNames[j]]!;

        // Sync A -> B
        final svB = encodeStateVector(docB);
        final diffA = encodeStateAsUpdate(docA, svB);
        if (diffA.length > 2) {
          applyUpdate(docB, diffA);
          fullySynced = false;
        }

        // Sync B -> A
        final svA = encodeStateVector(docA);
        final diffB = encodeStateAsUpdate(docB, svA);
        if (diffB.length > 2) {
          applyUpdate(docA, diffB);
          fullySynced = false;
        }
      }
    }
  }

  // 3. Verify Convergence
  final refClient = clientNames[0];
  final refText = docs[refClient]!.getText('note')!.toString();
  final refMapVal = docs[refClient]!.getMap('meta')!.toJson();
  final refArrVal = docs[refClient]!.getArray('list')!.toJson();
  
  final refMapStr = jsonEncode(_canonicalize(refMapVal));
  final refArrStr = jsonEncode(_canonicalize(refArrVal));

  for (var i = 1; i < clientNames.length; i++) {
    final client = clientNames[i];
    final textVal = docs[client]!.getText('note')!.toString();
    final mapVal = docs[client]!.getMap('meta')!.toJson();
    final arrVal = docs[client]!.getArray('list')!.toJson();
    
    final mapStr = jsonEncode(_canonicalize(mapVal));
    final arrStr = jsonEncode(_canonicalize(arrVal));

    if (textVal != refText || mapStr != refMapStr || arrStr != refArrStr) {
      print('=== REPRODUCIBILITY LOG ===');
      print('Divergence between client $refClient and client $client');
      print('Ref Text ($refClient): "$refText"');
      print('Ref Map ($refClient): $refMapStr');
      print('Ref Array ($refClient): $refArrStr');
      print('Client Text ($client): "$textVal"');
      print('Client Map ($client): $mapStr');
      print('Client Array ($client): $arrStr');
      print('--- Sequence of Operations ---');
      for (var opIdx = 0; opIdx < opLog.length; opIdx++) {
        print('  [$opIdx] ${opLog[opIdx]}');
      }
      throw Exception('Divergence detected in iteration $iterId!');
    }
  }
}

void runPhantomDeleteTest(int iterId, Random random) {
  final docA = Doc(DocOpts(gc: false, clientID: 65));
  final docB = Doc(DocOpts(gc: false, clientID: 66));

  docA.getText('note');
  docB.getText('note');

  const baseText = 'Hello World Example Text';

  docA.transact((tr) {
    docA.getText('note')!.insert(0, baseText);
  });
  final initUpdate = encodeStateAsUpdate(docA);
  applyUpdate(docB, initUpdate);

  // Pick overlapping position for concurrent insert and delete
  final pos = random.nextInt(baseText.length - 3) + 1;
  final insertStr = 'ins_${random.nextInt(1000)}_';
  final deleteLen = min(random.nextInt(5) + 1, baseText.length - pos);

  // A inserts at pos (simulating typing)
  docA.transact((tr) {
    docA.getText('note')!.insert(pos, insertStr);
  });

  // B concurrently deletes at same pos (phantom delete)
  docB.transact((tr) {
    docB.getText('note')!.delete(pos, deleteLen);
  });

  // Full bidirectional sync
  final svB = encodeStateVector(docB);
  final diffA = encodeStateAsUpdate(docA, svB);
  applyUpdate(docB, diffA);

  final svA = encodeStateVector(docA);
  final diffB = encodeStateAsUpdate(docB, svA);
  applyUpdate(docA, diffB);

  // Verify convergence
  final textA = docA.getText('note')!.toString();
  final textB = docB.getText('note')!.toString();
  if (textA != textB) {
    print('=== PHANTOM DELETE REPRODUCIBILITY LOG ===');
    print('Divergence in phantom delete test at iteration $iterId');
    print('Base text: "$baseText"');
    print('A insert at $pos: "$insertStr"');
    print('B delete at $pos length $deleteLen');
    print('Client A text: "$textA"');
    print('Client B text: "$textB"');
    throw Exception('Phantom delete divergence detected in iteration $iterId!');
  }
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
