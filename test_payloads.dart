import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final payloads = [
    [0x65, 0x00],
    [0x00, 0x65],
    [0x65, 0x65],
    [0x00, 0x00],
    [0x02, 0x00],
    [0x00, 0x02],
  ];
  for (final payload in payloads) {
    try {
      applyUpdate(doc, payload);
      print('OK: ${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    } catch (e) {
      print('ERR ${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}: $e');
    }
  }
}
