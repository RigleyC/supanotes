import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_attachment_url.dart';

void main() {
  test('builds a browser attachment URL without the API prefix', () {
    final url = shareLinkAttachmentUrl('share/token', 'attachment id');

    expect(url.path, '/s/share%2Ftoken/attachments/attachment%20id');
    expect(url.query, isEmpty);
    expect(url.fragment, isEmpty);
    expect(url.path, isNot(contains('/api/v1')));
  });
}
