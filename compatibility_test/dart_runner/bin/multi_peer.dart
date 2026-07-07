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
  print('Running Multi-Peer Spike (6 Clients)');
  print('=======================================');

  final random = Random(42);
  final clientNames = ['A', 'B', 'C', 'D', 'E', 'F'];
  final docs = <String, Doc>{};
  final localLengths = <String, int>{};

  for (final name in clientNames) {
    final clientID = name.codeUnitAt(0);
    docs[name] = Doc(DocOpts(gc: false, clientID: clientID));
    docs[name]!.getText('note');
    localLengths[name] = 0;
  }

  final stopwatch = Stopwatch()..start();

  const numRounds = 500;
  for (var round = 1; round <= numRounds; round++) {
    final roundUpdates = <String, Uint8List>{};

    // 1. Each peer makes 1-3 concurrent edits locally
    for (final name in clientNames) {
      final doc = docs[name]!;
      final text = doc.getText('note')!;
      var len = localLengths[name]!;

      final numEdits = random.nextInt(3) + 1;
      doc.transact((tr) {
        for (var e = 0; e < numEdits; e++) {
          if (random.nextBool() || len == 0) {
            final val = '$name${random.nextInt(10)} ';
            final idx = len > 0 ? random.nextInt(len + 1) : 0;
            text.insert(idx, val);
            len += val.length;
          } else {
            final idx = random.nextInt(len);
            final deleteLen = min(2, len - idx);
            text.delete(idx, deleteLen);
            len -= deleteLen;
          }
        }
      });
      localLengths[name] = len;
      roundUpdates[name] = encodeStateAsUpdate(doc);
    }

    // 2. Broadcast and merge round updates in random order to simulate latency/jitter
    for (final receiver in clientNames) {
      final updatesToMerge = roundUpdates.entries
          .where((entry) => entry.key != receiver)
          .map((entry) => entry.value)
          .toList()
        ..shuffle(random);

      for (final update in updatesToMerge) {
        applyUpdate(docs[receiver]!, update);
      }
    }

    if (round % 100 == 0) {
      print('Round $round / $numRounds completed...');
    }
  }

  // 3. Bidirectional Sync loop to guarantee convergence
  print('Performing final sync...');
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

  // 4. Verify Convergence
  final refClient = clientNames[0];
  final refText = docs[refClient]!.getText('note')!.toString();

  var convergenceError = false;
  for (var i = 1; i < clientNames.length; i++) {
    final client = clientNames[i];
    final textVal = docs[client]!.getText('note')!.toString();
    if (textVal != refText) {
      print('❌ Divergence detected between $refClient and $client!');
      convergenceError = true;
    }
  }

  stopwatch.stop();
  if (convergenceError) {
    exit(1);
  } else {
    print('=======================================');
    print('✅ Multi-Peer Spike Passed Successfully!');
    print('Total Time: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
    print('Final Converged Text Length: ${refText.length} characters');
    print('=======================================');
  }
}
