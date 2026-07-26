import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';

void main() {
  test('sanitizes note content, payloads, URLs and secrets before logging', () {
    final events = <Map<String, Object?>>[];
    NoteSyncDebug.logSink = (event, noteId, fields) {
      events.add({'event': event, 'noteId': noteId, ...fields});
    };
    addTearDown(() => NoteSyncDebug.logSink = null);

    NoteSyncDebug.log(
      'sync.failure',
      noteId: 'note-1',
      fields: {
        'token': 'secret-token',
        'url': 'https://example.com/private/path?token=secret',
        'payload': {
          'ops': [
            {'insert': 'full note content'},
          ],
        },
        'document': {
          'blocks': [
            {
              'id': 'b1',
              'type': 'paragraph',
              'delta': [
                {'insert': 'private note content'},
              ],
            },
          ],
        },
      },
    );

    final fields = events.single;
    expect(fields['token'], '<redacted>');
    expect(fields['url'], 'https://example.com');
    expect(fields['payload'], 'keys=ops ops=1');
    expect(fields['document'], 'b1:paragraph(chars=20)');
    expect(fields.values.join(' '), isNot(contains('secret-token')));
    expect(fields.values.join(' '), isNot(contains('private/path')));
    expect(fields.values.join(' '), isNot(contains('private note content')));
  });
}
