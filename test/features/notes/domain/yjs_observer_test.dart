import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  test('yjs_dart observer timing', () {
    final doc = Doc();
    final map = doc.getMap('nodes')!;
    
    bool isFlushing = false;
    bool observerFired = false;
    bool observerSawFlushing = false;
    
    map.observe((event, txn) {
      observerFired = true;
      observerSawFlushing = isFlushing;
    });
    
    isFlushing = true;
    doc.transact((txn) {
      map.set('key', 'value');
    });
    isFlushing = false;
    
    print('Observer Fired: $observerFired');
    print('Observer Saw Flushing: $observerSawFlushing');
  });
}
