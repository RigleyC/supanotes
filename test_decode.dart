import 'dart:typed_data';
import 'package:dart_crdt/dart_crdt.dart';
import 'package:supanotes/core/sync/yjs_sync_protocol_codec.dart';

void main() {
  final doc = Doc();
  final text = doc.getText('content');
  text.insertText(0, 'hello', attributes: DeltaAttributes.fromJson({ 'bold': true }));
  
  final update = encodeStateAsUpdate(doc);
  
  // Simulate Go server sending [2, ...update] (NO length!)
  final data = Uint8List(1 + update.length);
  data[0] = 2; // msgType = 2
  data.setRange(1, data.length, update);
  
  try {
    final (msgType, payload) = YjsSyncProtocolCodec.decode(data);
    print('Decoded msgType=$msgType payloadLen=${payload.length}');
    applyUpdate(Doc(), payload);
  } catch (e, st) {
    print('Failed: $e');
  }
}
