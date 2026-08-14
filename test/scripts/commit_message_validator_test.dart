import 'package:flutter_test/flutter_test.dart';

import '../../scripts/commit_message_validator.dart';

void main() {
  test('accepts conventional commit subjects', () {
    for (final message in [
      'feat(editor): add task block',
      'fix: preserve selection',
      'revert: restore previous sync path',
      'feat!: replace task protocol',
      'feat(editor): replace task protocol\n\nBREAKING CHANGE: remove old route',
      'Merge branch \'master\' into feature/editor',
    ]) {
      expect(
        CommitMessageValidator.validate(message).isValid,
        isTrue,
        reason: message,
      );
    }
  });

  test('rejects malformed or unknown commit subjects', () {
    for (final message in [
      'add task block',
      'feat(editor) add task block',
      'feat(editor): ',
      'unknown(editor): add task block',
    ]) {
      final result = CommitMessageValidator.validate(message);

      expect(result.isValid, isFalse, reason: message);
      expect(result.message, isNotEmpty);
    }
  });
}
