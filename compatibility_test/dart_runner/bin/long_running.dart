import 'dart:io';
import 'dart:math';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/structs/item.dart';
import 'package:yjs_dart/src/structs/content.dart';

void main() {
  // Override buggy _ContentStringStub with real ContentString reader
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);

  print('=======================================');
  print('Running Long-Running Spike (100,000 ops)');
  print('=======================================');

  final doc = Doc();
  final text = doc.getText('note')!;
  final random = Random(42);

  final startRss = ProcessInfo.currentRss;
  print('Initial Memory (RSS): ${(startRss / 1024 / 1024).toStringAsFixed(2)} MB');

  final stopwatch = Stopwatch()..start();
  var lapTime = stopwatch.elapsedMilliseconds;

  var localLen = 0;
  const totalOps = 100000;
  
  for (var i = 1; i <= totalOps; i++) {
    doc.transact((tr) {
      if (random.nextBool() || localLen == 0) {
        // Insert
        final val = 'word ';
        final idx = localLen > 0 ? random.nextInt(localLen + 1) : 0;
        text.insert(idx, val);
        localLen += val.length;
      } else {
        // Delete
        final idx = random.nextInt(localLen);
        final deleteLen = min(5, localLen - idx);
        text.delete(idx, deleteLen);
        localLen -= deleteLen;
      }
    });

    if (i % 10000 == 0) {
      final currentStopwatchTime = stopwatch.elapsedMilliseconds;
      final duration = currentStopwatchTime - lapTime;
      lapTime = currentStopwatchTime;
      
      final currentRss = ProcessInfo.currentRss;
      print('Ops: $i / $totalOps | Time for last 10k: ${duration}ms | Current Memory: ${(currentRss / 1024 / 1024).toStringAsFixed(2)} MB');
    }
  }

  stopwatch.stop();
  final finalRss = ProcessInfo.currentRss;
  
  // Verify final string length matches localLen
  final finalStr = text.toString();
  
  print('---------------------------------------');
  print('Total Time: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
  print('Final Memory (RSS): ${(finalRss / 1024 / 1024).toStringAsFixed(2)} MB');
  print('Memory Delta: ${((finalRss - startRss) / 1024 / 1024).toStringAsFixed(2)} MB');
  print('Final Doc length (toString): ${finalStr.length} characters');
  print('Final Doc length (localLen): $localLen');
  print('=======================================');
}
