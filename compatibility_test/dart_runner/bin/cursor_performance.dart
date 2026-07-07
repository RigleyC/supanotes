import 'dart:io';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/structs/item.dart';
import 'package:yjs_dart/src/structs/content.dart';

void main() {
  // Override buggy _ContentStringStub with real ContentString reader
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);

  print('=======================================');
  print('Running Cursor & Locality Benchmark');
  print('=======================================');

  // Benchmark 1: Typing Locality (Cursor Edits)
  // Simulate a user typing 10,000 characters sequentially
  {
    final doc = Doc();
    final text = doc.getText('note')!;
    final stopwatch = Stopwatch()..start();
    
    doc.transact((tr) {
      for (var i = 0; i < 10000; i++) {
        text.insert(i, 'a');
      }
    });
    
    stopwatch.stop();
    print('1. Typing Locality (10k chars at moving cursor):  ${stopwatch.elapsedMilliseconds}ms');
  }

  // Benchmark 2: Insert at Start of Document
  {
    final doc = Doc();
    final text = doc.getText('note')!;
    final stopwatch = Stopwatch()..start();
    
    doc.transact((tr) {
      for (var i = 0; i < 10000; i++) {
        text.insert(0, 'x');
      }
    });
    
    stopwatch.stop();
    print('2. Start of Document (10k chars at index 0):      ${stopwatch.elapsedMilliseconds}ms');
  }

  // Benchmark 3: Insert at End of Document
  {
    final doc = Doc();
    final text = doc.getText('note')!;
    final stopwatch = Stopwatch()..start();
    
    doc.transact((tr) {
      for (var i = 0; i < 10000; i++) {
        text.insert(i, 'y');
      }
    });
    
    stopwatch.stop();
    print('3. End of Document (10k chars at end):            ${stopwatch.elapsedMilliseconds}ms');
  }

  // Benchmark 4: Bulk Paste
  {
    final doc = Doc();
    final text = doc.getText('note')!;
    final bulkText = 'a' * 100000; // 100k block paste
    final stopwatch = Stopwatch()..start();
    
    doc.transact((tr) {
      text.insert(0, bulkText);
    });
    
    stopwatch.stop();
    print('4. Bulk Paste (100k chars block):                 ${stopwatch.elapsedMilliseconds}ms');
  }

  // Benchmark 5: Bulk Delete
  {
    final doc = Doc();
    final text = doc.getText('note')!;
    final bulkText = 'a' * 100000;
    doc.transact((tr) {
      text.insert(0, bulkText);
    });
    
    final stopwatch = Stopwatch()..start();
    
    doc.transact((tr) {
      text.delete(20000, 50000); // Delete 50k chars in one transaction
    });
    
    stopwatch.stop();
    print('5. Bulk Delete (50k chars block):                 ${stopwatch.elapsedMilliseconds}ms');
  }

  print('=======================================');
}
