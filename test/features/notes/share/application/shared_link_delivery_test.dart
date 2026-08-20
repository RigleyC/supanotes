import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/share/application/shared_link_delivery.dart';

void main() {
  test('extracts an HTTP URL and removes sentence punctuation', () {
    final uri = SharedLinkDelivery.extractUrlFromText(
      'Veja isto: https://example.com/post?id=1.',
    );

    expect(uri?.toString(), 'https://example.com/post?id=1');
  });

  test('rejects text without an HTTP URL', () {
    expect(SharedLinkDelivery.extractUrlFromText('texto sem link'), isNull);
    expect(SharedLinkDelivery.extractUrlFromText('ftp://example.com'), isNull);
  });
}
