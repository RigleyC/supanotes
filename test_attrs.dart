import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final text = doc.getText('content');
  
  // Try all possible attribute types
  text.insertText(0, 'hello', attributes: DeltaAttributes.fromJson({
    'bold': true,
    'size': 10,
    'weight': 1.5,
    'color': 'red',
    'composing': true,
  }));
  
  final update = encodeStateAsUpdate(doc);
  print('Update: ${update.length} bytes');
  
  final doc2 = Doc();
  try {
    applyUpdate(doc2, update);
    print('Success!');
  } catch (e, st) {
    print('Failed: $e\n$st');
  }
}
