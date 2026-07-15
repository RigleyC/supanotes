import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  for (final List<int> payload in [
    [0, 0],
    [],
    [0x65],
    [0x65, 0x00],
    [0x00, 0x65],
  ]) {
    try {
      applyUpdate(doc, Uint8List.fromList(payload));
      print('OK: ${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    } catch (e) {
      print('ERR ${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}: $e');
    }
  }
}
