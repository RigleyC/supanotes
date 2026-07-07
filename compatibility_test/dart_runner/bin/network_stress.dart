import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/structs/item.dart';
import 'package:yjs_dart/src/structs/content.dart';

void main() {
  // Override buggy _ContentStringStub with real ContentString reader
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);

  print('=======================================');
  print('Running Network Stress Spike (50,000 ops)');
  print('=======================================');

  final random = Random(42);
  final clientNames = ['A', 'B', 'C'];
  final docs = <String, Doc>{};
  final localLengths = <String, int>{};
  final networkQueues = <String, List<Uint8List>>{};

  for (final name in clientNames) {
    final clientID = name.codeUnitAt(0);
    docs[name] = Doc(DocOpts(gc: false, clientID: clientID));
    docs[name]!.getText('note');
    localLengths[name] = 0;
    networkQueues[name] = [];
  }

  final stopwatch = Stopwatch()..start();

  const totalOps = 50000;
  const batchSize = 20;
  
  for (var i = 1; i <= totalOps; i += batchSize) {
    // 1. Pick a random client and perform a batch of mutations locally
    final client = clientNames[random.nextInt(clientNames.length)];
    final doc = docs[client]!;
    final text = doc.getText('note')!;
    var len = localLengths[client]!;

    doc.transact((tr) {
      for (var b = 0; b < batchSize; b++) {
        if (random.nextBool() || len == 0) {
          // Insert
          final val = 'w${random.nextInt(10)} ';
          final idx = len > 0 ? random.nextInt(len + 1) : 0;
          text.insert(idx, val);
          len += val.length;
        } else {
          // Delete
          final idx = random.nextInt(len);
          final deleteLen = min(3, len - idx);
          text.delete(idx, deleteLen);
          len -= deleteLen;
        }
      }
    });
    localLengths[client] = len;

    // 2. Export update and distribute with 30% duplication chance
    final update = encodeStateAsUpdate(doc);
    for (final other in clientNames) {
      if (other != client) {
        networkQueues[other]!.add(update);
        if (random.nextDouble() < 0.3) {
          networkQueues[other]!.add(update); // Duplicate
        }
      }
    }

    // 3. Simulate random delivery/delay/reorder on a random client
    if (random.nextDouble() < 0.7) {
      final receiver = clientNames[random.nextInt(clientNames.length)];
      final queue = networkQueues[receiver]!;
      if (queue.isNotEmpty) {
        // Extreme reordering: shuffle queue
        queue.shuffle(random);
        // Deliver 1 to 5 random packets
        final numToDeliver = min(random.nextInt(5) + 1, queue.length);
        for (var d = 0; d < numToDeliver; d++) {
          final packet = queue.removeLast();
          applyUpdate(docs[receiver]!, packet);
        }
      }
    }

    if (i % 10000 < batchSize) {
      print('Ops: $i / $totalOps | Elapsed: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
    }
  }

  // 4. Flush all network queues
  print('Flushing all network queues...');
  for (final client in clientNames) {
    final queue = networkQueues[client]!;
    final doc = docs[client]!;
    while (queue.isNotEmpty) {
      final packet = queue.removeLast();
      applyUpdate(doc, packet);
    }
  }

  // 5. Bidirectional State Vector sync loops to ensure absolute convergence
  print('Performing final state vector sync...');
  var fullySynced = false;
  var syncLoops = 0;
  while (!fullySynced && syncLoops < 50) {
    fullySynced = true;
    syncLoops++;

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

  // 6. Verify Convergence
  final refClient = clientNames[0];
  final refText = docs[refClient]!.getText('note')!.toString();

  var convergenceError = false;
  for (var i = 1; i < clientNames.length; i++) {
    final client = clientNames[i];
    final textVal = docs[client]!.getText('note')!.toString();
    if (textVal != refText) {
      print('❌ Divergence detected between $refClient and $client!');
      print('Client $refClient text: "${refText.substring(0, min(100, refText.length))}..." (len: ${refText.length})');
      print('Client $client text: "${textVal.substring(0, min(100, textVal.length))}..." (len: ${textVal.length})');
      convergenceError = true;
    }
  }

  stopwatch.stop();
  if (convergenceError) {
    exit(1);
  } else {
    print('=======================================');
    print('✅ Network Stress Spike Passed Successfully!');
    print('Total Time: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
    print('Final Converged Text Length: ${refText.length} characters');
    print('=======================================');
  }
}
