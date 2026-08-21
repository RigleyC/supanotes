import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/share/domain/pending_share.dart';

void main() {
  test('parses from map and validates user ownership', () {
    final share = PendingShare.fromMap({
      'shareId': 's-123',
      'text': 'https://example.com',
      'noteId': 'note-1',
      'ownerUserId': 'user-1',
    });

    expect(share.shareId, 's-123');
    expect(share.text, 'https://example.com');
    expect(share.noteId, 'note-1');
    expect(share.ownerUserId, 'user-1');
    expect(share.isValidForUser('user-1'), isTrue);
    expect(share.isValidForUser('user-2'), isFalse);
  });

  test('accepts shares without specified owner user id for any user', () {
    final share = PendingShare.fromMap({
      'shareId': 's-456',
      'text': 'https://example.com',
    });

    expect(share.ownerUserId, isNull);
    expect(share.isValidForUser('user-1'), isTrue);
    expect(share.isValidForUser('user-2'), isTrue);
  });
}
