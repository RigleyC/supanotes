import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/domain/ot_document_codec.dart';

void main() {
  group('OtDocumentCodec Delta Suffix & Attribution Tests', () {
    const codec = OtDocumentCodec();

    test('retains unconsumed source text suffix after mid-text insert delta', () {
      final source = AttributedText('abcdef');
      final deltaOps = [
        {'retain': 3},
        {'insert': 'X'},
      ];

      final result = codec.applyDeltaToText(source, deltaOps);

      expect(result, isNotNull);
      expect(result!.toPlainText(), 'abcXdef');
    });

    test('retains attributions on unconsumed source text suffix after insert', () {
      final span = AttributedSpans();
      span.addAttribution(newAttribution: boldAttribution, start: 3, end: 6);
      final source = AttributedText('abcdef', span);

      final deltaOps = [
        {'retain': 2},
        {'insert': '123'},
      ];

      final result = codec.applyDeltaToText(source, deltaOps);

      expect(result, isNotNull);
      expect(result!.toPlainText(), 'ab123cdef');

      // Check that 'def' at indices 6..9 has bold attribution preserved
      final defMarker = result.spans.markers.where((m) => m.attribution == boldAttribution);
      expect(defMarker.isNotEmpty, true);
    });
  });
}
