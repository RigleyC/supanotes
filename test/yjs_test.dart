import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  test('YMap reads immediately', () {
    final doc = Doc();
    final map = doc.getMap<String>('nodes')!;
    
    doc.transact((txn) {
      map.set('test1', 'value1');
      final val = map.get('test1');
      print('Inside transact: $val');
    });
    
    final val2 = map.get('test1');
    print('Outside transact: $val2');
  });
}
